{ pkgs, ... }:

let
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
in
{
  systemd.services.switchbot-lock-api = {
    description = "SwitchBot Lock Ultra – local HTTP API for Homebridge";
    # bindsTo + wantedBy bluetooth.service: when bluetoothd crashes/restarts
    # we get stopped and started again with it. Otherwise bleak keeps a
    # dead scanner session and the lock goes "device not found" forever.
    wantedBy = [ "multi-user.target" "bluetooth.service" ];
    bindsTo = [ "bluetooth.service" ];
    after = [ "bluetooth.service" "bluetooth.target" ];
    unitConfig.ConditionPathExists = [
      "/var/lib/hydra-secrets/switchbot-mac"
      "/var/lib/hydra-secrets/switchbot-key-id"
      "/var/lib/hydra-secrets/switchbot-enc-key"
    ];
    serviceConfig = {
      ExecStart = "${pythonEnv}/bin/python3 ${./switchbot/lock-api.py}";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
