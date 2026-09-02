# Tapo plugs in Homebridge — troubleshooting notes

Tapo/Kasa plugs are driven by the `homebridge-kasa-python` plugin (installed
by `startup.sh` in `homebridge.nix`). Its config lives in the container at
`/homebridge/config.json` (`/data/homebridge` on hydra) under the
`KasaPython` platform — edit via the Homebridge UI (`http://10.253.10.2:8581`
→ Plugins → kasa-python), not nix.

## The big one: "Unsupported device" / new plug never appears (TPAP)

**Symptom (2026-09-01, Tapo P100(AU)):** plug is on WiFi, answers HTTP on
port 80, is listed in `manualDevices` — but discovery never adds it and the
logs show no attempt to contact it. Direct probe shows why:

```
docker exec homebridge /var/lib/homebridge/kasa-python/.venv/bin/kasa \
    --host <plug-ip> state

== Unsupported device ==
        Encrypt Type:       TPAP        <-- this
```

**Cause:** newer Tapo firmware speaks TP-Link's `TPAP` encryption, which
python-kasa does not support (open upstream:
[python-kasa#1590](https://github.com/python-kasa/python-kasa/issues/1590),
PR [#1706](https://github.com/python-kasa/python-kasa/pull/1706)). No plugin
update fixes it while that's open.

**Fix that worked:** force the plug to fall back to KLAP:

1. Tapo app → **Me → Third-Party Services → Third-Party Compatibility** —
   toggle it **off, then on**. (Account-level setting. It is NOT in the
   per-device settings, which is where you'll look first.)
2. Power-cycle the plug at the wall — it re-reads the account flag on boot.
3. Re-run the `kasa --host <ip> state` probe: `Encrypt Type` should now be
   `KLAP`, and the same command with `--username <tp-link email>
   --password <pw>` should print full device state.
4. Restart Homebridge; the plug appears.

Note the toggle was already "on" when this happened — a plug that joined the
account later still came up TPAP until the off/on cycle + reboot.

## Other gotchas that cost time (same debugging session)

- **`includeMacAddresses` is an allow-list.** If set, ONLY those MACs become
  accessories — discovery hits and `manualDevices` entries for other MACs
  are silently dropped. Remove it unless deliberately pinning.
- **`hideHomeKitMatter` defaults to `true`:** Matter-capable models (suffix
  M, e.g. P110M) are silently filtered. Either set it false, or better,
  pair Matter plugs directly with the Home app and skip Homebridge.
- **All Tapo devices need credentials:** `enableCredentials: true` +
  TP-Link account email/password. Keep the email lowercase (known
  python-kasa auth quirk).
- **`manualDevices` entries are just `{"host": "<ip>"}`** — give the plugs
  DHCP reservations in UniFi so the IPs don't drift.
- **Tapo's HTTP server answers `Server: SHIP 2.0`** — that's TP-Link's
  embedded server, not an EEBUS energy device. A 200 on port 80 only proves
  reachability, not protocol support (see TPAP above).
- **Moved/renamed devices keep their HomeKit identity** (keyed on device
  id): repoint Home-app automations at the right accessory and clear stale
  tiles via UI → Settings → Remove Single Cached Accessory.
- **Energy monitoring** (P110 etc.): needs `enableEnergyMonitoring: true`;
  wattage shows in the Eve app, never in the Home app.

## Diagnostic toolbox

```sh
# What does python-kasa (the exact installed version) think of a device?
docker exec homebridge /var/lib/homebridge/kasa-python/.venv/bin/kasa \
    --host <ip> state          # add --username/--password for full state

# Broadcast discovery, same library:
docker exec homebridge /var/lib/homebridge/kasa-python/.venv/bin/kasa discover

# Plugin config as actually loaded:
docker exec homebridge cat /homebridge/config.json

# Verbose plugin behaviour: enable Homebridge debug mode in the UI, and set
# advancedPythonLogging: true in the plugin config to see the python side
# (discovery + per-device connection attempts).
```

andre is in the `docker` group on hydra, so all of this works without sudo.
