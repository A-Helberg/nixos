#!/usr/bin/env python3
"""
HTTP API server for the SwitchBot Lock Ultra. Listens on 127.0.0.1:7474.

State is cached in memory and kept fresh via:
  - One GATT connection on startup (battery, firmware, calibration, etc.)
  - Passive BLE advertisement scanning for live status/door_open updates

Routes:
  GET  /status  → {"status": "LOCKED|UNLOCKED|...", "door_open": bool, "battery": int, ...}
  POST /lock    → {"ok": true}
  POST /unlock  → {"ok": true}

Every HTTP request is served from cache — no BLE operation per poll.
"""

import asyncio
from bleak import BLEDevice, BleakScanner
from aiohttp import web
from switchbot import SwitchbotLock
from switchbot.const import SwitchbotModel


def _read(path: str) -> str:
    with open(path) as f:
        return f.read().strip()


MAC     = _read("/var/lib/hydra-secrets/switchbot-mac").upper()
KEY_ID  = _read("/var/lib/hydra-secrets/switchbot-key-id")
ENC_KEY = _read("/var/lib/hydra-secrets/switchbot-enc-key")

SWITCHBOT_MFR_ID = 0x0969

_LOCK_STATUS = {
    0: "LOCKED",
    1: "UNLOCKED",
    2: "LOCKING",
    3: "UNLOCKING",
    4: "LOCKING_STOP",
    5: "UNLOCKING_STOP",
    6: "NOT_FULLY_LOCKED",
}

# Cached state — served directly by /status
_state: dict = {
    "status": "UNKNOWN",
    "door_open": None,
    "battery": None,
    "calibration": None,
    "unclosed_alarm": None,
    "unlocked_alarm": None,
    "firmware": None,
}

# Cached BLEDevice from the scanner — avoids starting a second scanner for GATT ops
_device: BLEDevice | None = None

# Serialises GATT operations so they don't step on each other or the scanner
_ble_lock = asyncio.Lock()


def _parse_adv(mfr_data: bytes) -> dict | None:
    if len(mfr_data) < 9:
        return None
    status_bits = (mfr_data[7] & 0b01111000) >> 3
    door_open   = bool(mfr_data[8] & 0b00010000)
    return {"status": _LOCK_STATUS.get(status_bits, "UNKNOWN"), "door_open": door_open}


def _make_lock(device: BLEDevice) -> SwitchbotLock:
    return SwitchbotLock(device, key_id=KEY_ID, encryption_key=ENC_KEY,
                         model=SwitchbotModel.LOCK_ULTRA)


async def _gatt_refresh(device: BLEDevice) -> None:
    """Full GATT read — used once at startup for slow-changing fields."""
    lock = _make_lock(device)
    info = await lock.get_basic_info()
    if info is None:
        return
    raw_status = info.get("status")
    _state.update({
        "status": raw_status.name if hasattr(raw_status, "name") else str(raw_status) if raw_status else _state["status"],
        "door_open":      info.get("door_open"),
        "battery":        info.get("battery"),
        "calibration":    info.get("calibration"),
        "unclosed_alarm": info.get("unclosed_alarm"),
        "unlocked_alarm": info.get("unlocked_alarm"),
        "firmware":       info.get("firmware"),
    })


async def _scan_loop() -> None:
    """
    Passive BLE advertisement scanner.
    - Caches the BLEDevice object for reuse by GATT operations.
    - Updates status/door_open from advertisements in real time.
    - Does an initial GATT refresh once the device is first seen.
    """
    global _device
    initial_refresh_done = False

    def on_advertisement(device: BLEDevice, adv_data) -> None:
        nonlocal initial_refresh_done
        if device.address.upper() != MAC:
            return

        # Always refresh the cached device reference (address may stay the same
        # but the object carries updated RSSI / connection params).
        global _device
        _device = device

        mfr = adv_data.manufacturer_data.get(SWITCHBOT_MFR_ID)
        if mfr:
            parsed = _parse_adv(bytes(mfr))
            if parsed:
                _state["status"]   = parsed["status"]
                _state["door_open"] = parsed["door_open"]

        # Trigger the one-time GATT refresh after first advertisement
        if not initial_refresh_done:
            initial_refresh_done = True
            asyncio.get_event_loop().create_task(_initial_gatt_refresh())

    async with BleakScanner(detection_callback=on_advertisement):
        while True:
            await asyncio.sleep(3600)


async def _initial_gatt_refresh() -> None:
    global _device
    if _device is None:
        return
    async with _ble_lock:
        try:
            await _gatt_refresh(_device)
            print(f"Initial GATT refresh complete: {_state}", flush=True)
        except Exception as e:
            print(f"Initial GATT refresh failed: {e}", flush=True)


# ---------------------------------------------------------------------------
# HTTP handlers — all served from cache
# ---------------------------------------------------------------------------

async def handle_status(request: web.Request) -> web.Response:
    return web.json_response(_state)


async def handle_lock(request: web.Request) -> web.Response:
    return await _send_command("lock")


async def handle_unlock(request: web.Request) -> web.Response:
    return await _send_command("unlock")


async def _send_command(command: str) -> web.Response:
    global _device
    if _device is None:
        return web.json_response({"error": "Device not yet discovered"}, status=503)
    try:
        async with _ble_lock:
            lock = _make_lock(_device)
            ok = await (lock.lock() if command == "lock" else lock.unlock())
        if not ok:
            return web.json_response({"error": f"{command} command failed"}, status=500)
        # Optimistically update cached status
        _state["status"] = "LOCKED" if command == "lock" else "UNLOCKED"
        return web.json_response({"ok": True})
    except Exception as e:
        return web.json_response({"error": str(e)}, status=500)


async def on_startup(app: web.Application) -> None:
    asyncio.create_task(_scan_loop())


app = web.Application()
app.on_startup.append(on_startup)
app.router.add_get("/status", handle_status)
app.router.add_post("/lock", handle_lock)
app.router.add_post("/unlock", handle_unlock)

if __name__ == "__main__":
    web.run_app(app, host="127.0.0.1", port=7474)
