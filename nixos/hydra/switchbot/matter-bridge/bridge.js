/**
 * Matter bridge for SwitchBot Lock Ultra.
 *
 * Exposes the lock as a Matter DoorLock device, controllable from HomeKit
 * (and any other Matter controller). All BLE communication is delegated to
 * the `switchbot-lock` CLI that must already be on PATH.
 *
 * Storage (commissioning data, fabric keys, etc.) is kept under the
 * directory pointed to by MATTER_STORAGE_PATH (default: ./matter-storage).
 *
 * On first run the QR code / pairing code is printed to stdout – scan it
 * with your Home app to commission the bridge.
 */

import { Endpoint, Environment, ServerNode, StorageService, VendorId } from "@matter/main";
import { BridgedDeviceBasicInformationServer } from "@matter/main/behaviors/bridged-device-basic-information";
import { DoorLockServer } from "@matter/main/behaviors/door-lock";
import { DoorLockDevice } from "@matter/main/devices/door-lock";
import { AggregatorEndpoint } from "@matter/main/endpoints/aggregator";
import { DoorLock } from "@matter/main/clusters/door-lock";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { readFileSync } from "node:fs";

const execFileAsync = promisify(execFile);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Parse `switchbot-lock status` stdout into a DoorLock.LockState value. */
function parseLockState(stdout) {
    const match = stdout.match(/^Status:\s+(\w+)/m);
    if (!match) return null;
    switch (match[1].toUpperCase()) {
        case "LOCKED":           return DoorLock.LockState.Locked;
        case "UNLOCKED":         return DoorLock.LockState.Unlocked;
        case "NOT_FULLY_LOCKED": return DoorLock.LockState.NotFullyLocked;
        default:                 return null;  // LOCKING/UNLOCKING/BLOCKED — skip update
    }
}

/** Query the physical lock and return its current LockState (or null on error). */
async function queryLockState() {
    try {
        const { stdout } = await execFileAsync("switchbot-lock", ["status"]);
        return parseLockState(stdout);
    } catch (err) {
        console.error("[bridge] Status query failed:", err.message);
        return null;
    }
}

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const STORAGE_PATH = process.env.MATTER_STORAGE_PATH ?? "./matter-storage";
const PASSCODE     = parseInt(process.env.MATTER_PASSCODE     ?? "20202021", 10);
const DISCRIMINATOR = parseInt(process.env.MATTER_DISCRIMINATOR ?? "3840",     10);
const PORT         = parseInt(process.env.MATTER_PORT         ?? "5540",     10);
const UNIQUE_ID    = process.env.MATTER_UNIQUE_ID ?? "switchbot-lock-ultra-bridge";

// ---------------------------------------------------------------------------
// Custom DoorLock behavior – shells out to `switchbot-lock`
// ---------------------------------------------------------------------------

const POLL_INTERVAL_MS = 60_000; // sync state from the lock every 60 s

class SwitchbotLockServer extends DoorLockServer {
    async initialize() {
        this.state.operatingMode = DoorLock.OperatingMode.Normal;
        await super.initialize();

        // Sync the real lock state before announcing to controllers
        const state = await queryLockState();
        if (state !== null) {
            this.state.lockState = state;
            console.log(`[bridge] Initial lock state: ${Object.keys(DoorLock.LockState).find(k => DoorLock.LockState[k] === state)}`);
        }

        // Keep polling so HomeKit stays in sync with manual lock operations
        this[Symbol.for("pollInterval")] = setInterval(async () => {
            const polled = await queryLockState();
            if (polled !== null && polled !== this.state.lockState) {
                console.log("[bridge] Lock state changed externally, updating Matter state.");
                this.state.lockState = polled;
            }
        }, POLL_INTERVAL_MS);
    }

    async [Symbol.asyncDispose]() {
        clearInterval(this[Symbol.for("pollInterval")]);
    }

    async lockDoor() {
        console.log("[bridge] Sending lock command to SwitchBot...");
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
        console.log("[bridge] Sending unlock command to SwitchBot...");
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

process.on("SIGINT", async () => {
    console.log("[bridge] Received SIGINT, shutting down...");
    await server.close();
    process.exit(0);
});

process.on("SIGTERM", async () => {
    console.log("[bridge] Received SIGTERM, shutting down...");
    await server.close();
    process.exit(0);
});
