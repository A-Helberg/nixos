/**
 * Matter bridge for SwitchBot Lock Ultra.
 *
 * Exposes the lock as a Matter DoorLock device, controllable from HomeKit
 * (and any other Matter controller).
 *
 * State updates are driven by passive BLE advertisement scanning via the
 * `switchbot-lock scan` command (Python/bleak).  The lock broadcasts its
 * status every few seconds so changes are reflected within seconds of
 * occurring physically.
 *
 * A GATT status query is also performed once at startup for an immediate
 * accurate initial state, and every 5 minutes as a safety-net fallback.
 *
 * On first run the QR code / pairing code is printed to stdout – scan it
 * with your Home app to commission the bridge.
 */

import { Endpoint, Environment, ServerNode, VendorId } from "@matter/main";
import { BridgedDeviceBasicInformationServer } from "@matter/main/behaviors/bridged-device-basic-information";
import { DoorLockServer } from "@matter/main/behaviors/door-lock";
import { DoorLockDevice } from "@matter/main/devices/door-lock";
import { AggregatorEndpoint } from "@matter/main/endpoints/aggregator";
import { DoorLock } from "@matter/main/clusters/door-lock";
import { execFile, spawn } from "node:child_process";
import { promisify } from "node:util";
import { readFileSync } from "node:fs";

const execFileAsync = promisify(execFile);

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const STORAGE_PATH  = process.env.MATTER_STORAGE_PATH  ?? "./matter-storage";
const PASSCODE      = parseInt(process.env.MATTER_PASSCODE      ?? "20202021", 10);
const DISCRIMINATOR = parseInt(process.env.MATTER_DISCRIMINATOR ?? "3840",     10);
const PORT          = parseInt(process.env.MATTER_PORT          ?? "5540",     10);
const UNIQUE_ID     = process.env.MATTER_UNIQUE_ID ?? "switchbot-lock-ultra-bridge";

// GATT fallback poll — BLE advertisements are the primary signal.
const FALLBACK_POLL_MS = 5 * 60_000;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Convert `switchbot-lock status` stdout → LockState enum value. */
function parseLockState(stdout) {
    const match = stdout.match(/^Status:\s+(\w+)/m);
    if (!match) return null;
    switch (match[1].toUpperCase()) {
        case "LOCKED":           return DoorLock.LockState.Locked;
        case "UNLOCKED":         return DoorLock.LockState.Unlocked;
        case "NOT_FULLY_LOCKED": return DoorLock.LockState.NotFullyLocked;
        default:                 return null; // LOCKING/UNLOCKING — transient
    }
}

/** GATT status query via the Python CLI. */
async function queryStatus() {
    try {
        const { stdout } = await execFileAsync("switchbot-lock", ["status"]);
        return { lockState: parseLockState(stdout) };
    } catch (err) {
        console.error("[bridge] GATT status query failed:", err.message);
        return { lockState: null };
    }
}

/** Convert a status string from the scanner JSON → LockState. */
function statusToLockState(status) {
    switch ((status ?? "").toUpperCase()) {
        case "LOCKED":           return DoorLock.LockState.Locked;
        case "UNLOCKED":         return DoorLock.LockState.Unlocked;
        case "NOT_FULLY_LOCKED": return DoorLock.LockState.NotFullyLocked;
        default:                 return null; // LOCKING/UNLOCKING — transient, skip
    }
}

// ---------------------------------------------------------------------------
// Custom DoorLock behavior
// ---------------------------------------------------------------------------

class SwitchbotLockServer extends DoorLockServer {
    async initialize() {
        this.state.operatingMode = DoorLock.OperatingMode.Normal;
        await super.initialize();

        // Get accurate initial state via GATT before announcing to controllers.
        const initial = await queryStatus();
        if (initial.lockState !== null) {
            this.state.lockState = initial.lockState;
            console.log(`[bridge] Initial lock state: ${initial.lockState}`);
        }

        // --- BLE advertisement scanner (primary update path) ---
        // Spawns `switchbot-lock scan` which runs forever and emits a JSON
        // line on stdout whenever lock state or door-open changes.
        //
        // State updates are wrapped with this.callback() so they run inside
        // a Matter act/transaction and are properly broadcast to subscribers.
        this._startScanner();

        // --- GATT fallback poll ---
        this._pollInterval = setInterval(async () => {
            const { lockState } = await queryStatus();
            if (lockState !== null && lockState !== this.state.lockState) {
                console.log("[bridge] Fallback poll: lock state changed.");
                this.state.lockState = lockState;
            }
        }, FALLBACK_POLL_MS);
    }

    _startScanner() {
        // Wrap the handler so it runs inside a Matter transaction, ensuring
        // state changes are committed and broadcast to all subscribers.
        const handleLine = this.callback((state) => {
            const newLockState = statusToLockState(state.status);
            if (newLockState !== null && newLockState !== this.state.lockState) {
                console.log(`[bridge] BLE adv: lock state → ${newLockState}`);
                this.state.lockState = newLockState;
            }
            if (typeof state.door_open === "boolean") {
                console.log(`[bridge] BLE adv: door → ${state.door_open ? "OPEN" : "CLOSED"}`);
            }
        });

        const proc = spawn("switchbot-lock", ["scan"], {
            stdio: ["ignore", "pipe", "inherit"],
        });

        this._scannerProc = proc;

        let buf = "";
        proc.stdout.on("data", (chunk) => {
            buf += chunk.toString();
            const lines = buf.split("\n");
            buf = lines.pop(); // keep incomplete trailing line
            for (const line of lines) {
                if (!line.trim()) continue;
                try {
                    handleLine(JSON.parse(line));
                } catch {
                    console.warn("[bridge] Scanner: bad JSON:", line);
                }
            }
        });

        proc.on("exit", (code, signal) => {
            console.warn(`[bridge] Scanner exited (code=${code} signal=${signal}), restarting in 5s...`);
            this._scannerProc = null;
            setTimeout(() => {
                if (!this._destroyed) this._startScanner();
            }, 5_000);
        });

        proc.on("error", (err) => {
            console.error("[bridge] Scanner process error:", err.message);
        });
    }

    async [Symbol.asyncDispose]() {
        this._destroyed = true;
        clearInterval(this._pollInterval);
        this._scannerProc?.kill("SIGTERM");
    }

    async lockDoor() {
        console.log("[bridge] Sending lock command...");
        try {
            const { stdout } = await execFileAsync("switchbot-lock", ["lock"]);
            if (stdout) process.stdout.write(stdout);
            this.state.lockState = DoorLock.LockState.Locked;
            console.log("[bridge] Door locked.");
        } catch (err) {
            console.error("[bridge] Lock command failed:", err.message);
            throw err;
        }
    }

    async unlockDoor() {
        console.log("[bridge] Sending unlock command...");
        try {
            const { stdout } = await execFileAsync("switchbot-lock", ["unlock"]);
            if (stdout) process.stdout.write(stdout);
            this.state.lockState = DoorLock.LockState.Unlocked;
            console.log("[bridge] Door unlocked.");
        } catch (err) {
            console.error("[bridge] Unlock command failed:", err.message);
            throw err;
        }
    }
}

// ---------------------------------------------------------------------------
// Matter server
// ---------------------------------------------------------------------------

const environment = Environment.default;
environment.vars.set("storage.path", STORAGE_PATH);

const server = await ServerNode.create({
    id: UNIQUE_ID,

    network: { port: PORT },

    commissioning: {
        passcode: PASSCODE,
        discriminator: DISCRIMINATOR,
    },

    productDescription: {
        name: "SwitchBot Lock Bridge",
        deviceType: AggregatorEndpoint.deviceType,
    },

    basicInformation: {
        vendorName: "SwitchBot",
        vendorId: VendorId(0xfff1),
        nodeLabel: "SwitchBot Lock Bridge",
        productName: "Lock Ultra Bridge",
        productLabel: "Lock Ultra Bridge",
        productId: 0x8000,
        serialNumber: `${UNIQUE_ID}-sn`,
        uniqueId: UNIQUE_ID,
    },
});

const aggregator = new Endpoint(AggregatorEndpoint, { id: "aggregator" });
await server.add(aggregator);

const lockEndpoint = new Endpoint(
    DoorLockDevice.with(BridgedDeviceBasicInformationServer, SwitchbotLockServer),
    {
        id: "door-lock",
        bridgedDeviceBasicInformation: {
            nodeLabel: "Front Door",
            productName: "Lock Ultra",
            productLabel: "Lock Ultra",
            serialNumber: `${UNIQUE_ID}-lock`,
            reachable: true,
        },
        doorLock: {
            lockType: DoorLock.LockType.DeadBolt,
            actuatorEnabled: true,
        },
    },
);
await aggregator.add(lockEndpoint);

await server.start();

process.on("SIGINT",  async () => { await server.close(); process.exit(0); });
process.on("SIGTERM", async () => { await server.close(); process.exit(0); });
