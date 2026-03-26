{ pkgs, lib, ... }:

let
  nodejs = pkgs.nodejs_22;

  pySwitchbot = pkgs.python3Packages.buildPythonPackage rec {
    pname = "pyswitchbot";
    version = "2.0.0";
    pyproject = true;
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/0c/ff/064193cfef792eecf59539eff5ada46602587e86dc097ceed08d5afd7e3c/pyswitchbot-2.0.0.tar.gz";
      sha256 = "1mbysp8cgdvsvwax74xh037ig1ynlxdvfdb8xyqsf26by2g5ihf3";
    };
    build-system = with pkgs.python3Packages; [ setuptools ];
    propagatedBuildInputs = with pkgs.python3Packages; [
      aiohttp
      bleak
      pkgs.python3Packages."bleak-retry-connector"
      cryptography
      pyopenssl
    ];
    doCheck = false;
  };

  pythonEnv = pkgs.python3.withPackages (_: [ pySwitchbot ]);

  # Wrapper that reads credentials from secrets files so you just run:
  #   switchbot-lock lock | unlock | status
  switchbot-lock = pkgs.writeShellScriptBin "switchbot-lock" ''
    set -euo pipefail
    MAC=$(cat /var/lib/hydra-secrets/switchbot-mac)
    KEY_ID=$(cat /var/lib/hydra-secrets/switchbot-key-id)
    ENC_KEY=$(cat /var/lib/hydra-secrets/switchbot-enc-key)
    exec ${pythonEnv}/bin/python3 ${./switchbot/switchbot-lock} \
      -d "$MAC" -k "$KEY_ID" -e "$ENC_KEY" "$@"
  '';

  # One-time helper to retrieve keys from the SwitchBot cloud
  switchbot-get-key = pkgs.writeShellScriptBin "switchbot-get-key" ''
    exec ${pythonEnv}/bin/python3 ${./switchbot/get-encryption-key} "$@"
  '';

  # ---------------------------------------------------------------------------
  # Matter bridge (Node.js, @matter/main)
  # ---------------------------------------------------------------------------

  matterBridge = pkgs.buildNpmPackage {
    pname = "switchbot-matter-bridge";
    version = "1.0.0";
    src = ./switchbot/matter-bridge;
    npmDepsHash = "sha256-vkfCsdP1EBMKq/HVyoymQidMEH0Pg90YZb0wzp+S7zI=";

    nodejs = nodejs;
    dontBuild = true;

    nativeBuildInputs = [ pkgs.makeWrapper ];

    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/matter-bridge
      cp bridge.js package.json $out/lib/matter-bridge/
      cp -r node_modules $out/lib/matter-bridge/
      mkdir -p $out/bin
      makeWrapper ${nodejs}/bin/node $out/bin/switchbot-matter-bridge \
        --add-flags "$out/lib/matter-bridge/bridge.js"
      runHook postInstall
    '';
  };
in
{
  hardware.bluetooth.enable = true;

  environment.systemPackages = [ switchbot-lock switchbot-get-key ];

  # Matter commissioning + operational ports
  networking.firewall.allowedUDPPorts = [ 5353 5540 ];
  networking.firewall.allowedTCPPorts = [ 5540 ];

  # ---------------------------------------------------------------------------
  # Matter bridge service
  # ---------------------------------------------------------------------------

  systemd.services.switchbot-matter-bridge = {
    description = "SwitchBot Lock Ultra – Matter Bridge";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "bluetooth.target" ];
    wants = [ "network-online.target" ];
    unitConfig.ConditionPathExists = [
      "/var/lib/hydra-secrets/switchbot-mac"
      "/var/lib/hydra-secrets/switchbot-key-id"
      "/var/lib/hydra-secrets/switchbot-enc-key"
    ];

    # switchbot-lock must be on PATH so the bridge can exec it
    path = [ switchbot-lock ];

    environment = {
      MATTER_STORAGE_PATH = "/var/lib/switchbot-matter-bridge";
    };

    serviceConfig = {
      ExecStart = "${matterBridge}/bin/switchbot-matter-bridge";
      StateDirectory = "switchbot-matter-bridge";
      WorkingDirectory = "/var/lib/switchbot-matter-bridge";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  # Secrets must be populated manually on the machine:
  #   /var/lib/hydra-secrets/switchbot-mac       – BLE MAC address
  #   /var/lib/hydra-secrets/switchbot-key-id    – key ID from switchbot-get-key
  #   /var/lib/hydra-secrets/switchbot-enc-key   – encryption key from switchbot-get-key
}
