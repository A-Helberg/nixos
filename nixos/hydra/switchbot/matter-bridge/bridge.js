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

class SwitchbotLockServer extends DoorLockServer {
    override async lockDoor() {
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

    override async unlockDoor() {
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
        serialNumber: UNIQUE_ID,
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
            lockState: DoorLock.LockState.Locked,
            lockType: DoorLock.LockType.DeadBolt,
            actuatorEnabled: true,
        },
    },
);
await aggregator.add(lockEndpoint);

await server.start();
