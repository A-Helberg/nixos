'use strict';

const http = require('http');

const PLUGIN_NAME = 'homebridge-switchbot-lock-ultra';
const PLATFORM_NAME = 'SwitchBotLockUltra';
const API_HOST = '127.0.0.1';
const API_PORT = 7474;
const TIMEOUT_MS = 30_000;

module.exports = (api) => {
  api.registerPlatform(PLUGIN_NAME, PLATFORM_NAME, SwitchBotLockUltraPlatform);
};

function apiRequest(method, path) {
  return new Promise((resolve, reject) => {
    const req = http.request(
      { hostname: API_HOST, port: API_PORT, path, method },
      (res) => {
        let body = '';
        res.on('data', (chunk) => { body += chunk; });
        res.on('end', () => {
          try {
            const data = JSON.parse(body);
            if (res.statusCode >= 200 && res.statusCode < 300) {
              resolve(data);
            } else {
              reject(new Error(data.error || `HTTP ${res.statusCode}`));
            }
          } catch {
            reject(new Error(`Bad response: ${body}`));
          }
        });
      },
    );
    req.setTimeout(TIMEOUT_MS, () => { req.destroy(new Error('Request timed out')); });
    req.on('error', reject);
    req.end();
  });
}

class SwitchBotLockUltraPlatform {
  constructor(log, config, api) {
    this.log = log;
    this.config = config;
    this.api = api;
    this.accessories = [];

    api.on('didFinishLaunching', () => this.syncAccessory());
  }

  configureAccessory(accessory) {
    this.accessories.push(accessory);
  }

  syncAccessory() {
    const uuid = this.api.hap.uuid.generate('switchbot-lock-ultra-singleton');
    const existing = this.accessories.find((a) => a.UUID === uuid);
    const accessory = existing
      || new this.api.platformAccessory(this.config.name || 'Front Door', uuid);

    this.setupServices(accessory);

    if (!existing) {
      this.api.registerPlatformAccessories(PLUGIN_NAME, PLATFORM_NAME, [accessory]);
    }
  }

  setupServices(accessory) {
    const { Service, Characteristic } = this.api.hap;

    accessory
      .getService(Service.AccessoryInformation)
      .setCharacteristic(Characteristic.Manufacturer, 'SwitchBot')
      .setCharacteristic(Characteristic.Model, 'Lock Ultra')
      .setCharacteristic(Characteristic.SerialNumber, 'custom-plugin-v1');

    let lockService = accessory.getService(Service.LockMechanism);
    if (!lockService) {
      lockService = accessory.addService(Service.LockMechanism);
    }

    lockService
      .getCharacteristic(Characteristic.LockCurrentState)
      .onGet(() => this.getCurrentState());

    lockService
      .getCharacteristic(Characteristic.LockTargetState)
      .onGet(() => this.getTargetState())
      .onSet((value) => this.setTargetState(value, lockService));

    this.startPolling(lockService);
  }

  startPolling(lockService) {
    const { LockCurrentState, LockTargetState } = this.api.hap.Characteristic;
    const POLL_MS = 5000;

    const poll = async () => {
      try {
        const { status } = await apiRequest('GET', '/status');
        const current = this.mapStatus(status);
        lockService.updateCharacteristic(LockCurrentState, current);
        const target = current === LockCurrentState.SECURED
          ? LockTargetState.SECURED
          : LockTargetState.UNSECURED;
        lockService.updateCharacteristic(LockTargetState, target);
      } catch {
        // silently skip — stale cache is fine
      }
      setTimeout(poll, POLL_MS);
    };

    setTimeout(poll, POLL_MS);
  }

  async getCurrentState() {
    const { LockCurrentState } = this.api.hap.Characteristic;
    try {
      const { status } = await apiRequest('GET', '/status');
      return this.mapStatus(status);
    } catch (err) {
      this.log.error('getCurrentState failed:', err.message);
      return LockCurrentState.UNKNOWN;
    }
  }

  async getTargetState() {
    const { LockCurrentState, LockTargetState } = this.api.hap.Characteristic;
    const current = await this.getCurrentState();
    return current === LockCurrentState.SECURED
      ? LockTargetState.SECURED
      : LockTargetState.UNSECURED;
  }

  async setTargetState(value, lockService) {
    const { LockCurrentState, LockTargetState } = this.api.hap.Characteristic;
    const command = value === LockTargetState.SECURED ? 'lock' : 'unlock';
    this.log.info(`Sending command: ${command}`);
    try {
      await apiRequest('POST', `/${command}`);
      const newCurrent = value === LockTargetState.SECURED
        ? LockCurrentState.SECURED
        : LockCurrentState.UNSECURED;
      lockService.updateCharacteristic(LockCurrentState, newCurrent);
    } catch (err) {
      this.log.error(`${command} failed:`, err.message);
      throw new this.api.hap.HapStatusError(
        this.api.hap.HAPStatus.SERVICE_COMMUNICATION_FAILURE,
      );
    }
  }

  mapStatus(status) {
    const { LockCurrentState } = this.api.hap.Characteristic;
    switch (status) {
      case 'LOCKED':           return LockCurrentState.SECURED;
      case 'UNLOCKED':         return LockCurrentState.UNSECURED;
      case 'NOT_FULLY_LOCKED': return LockCurrentState.UNSECURED;
      case 'LOCKING':          return LockCurrentState.SECURED;
      case 'UNLOCKING':        return LockCurrentState.UNSECURED;
      case 'LOCKING_STOP':
      case 'UNLOCKING_STOP':   return LockCurrentState.JAMMED;
      default:                 return LockCurrentState.UNKNOWN;
    }
  }
}
