{ pkgs, ... }:
{
  hardware.bluetooth.enable = true;

  systemd.tmpfiles.rules = [
    "d /data/homebridge 0700 root root -"
  ];

  system.activationScripts.homebridge-plugin-setup = {
    text = ''
      # Install kasa plugin via startup.sh (needs hb-service from inside the container)
      mkdir -p /data/homebridge
      cat > /data/homebridge/startup.sh << 'EOF'
#!/bin/bash
hb-service add homebridge-kasa-python 2>/dev/null || true
EOF
      chmod +x /data/homebridge/startup.sh

      # Copy our local plugin straight into Homebridge's node_modules so it's
      # discovered automatically — this path is on the persisted volume.
      mkdir -p /data/homebridge/node_modules/homebridge-switchbot-lock-ultra
      cp ${./homebridge-switchbot-lock-ultra/package.json} /data/homebridge/node_modules/homebridge-switchbot-lock-ultra/package.json
      cp ${./homebridge-switchbot-lock-ultra/index.js}     /data/homebridge/node_modules/homebridge-switchbot-lock-ultra/index.js
    '';
    deps = [];
  };

  virtualisation.oci-containers.backend = "docker";
  virtualisation.oci-containers.containers.homebridge = {
    image = "ghcr.io/homebridge/homebridge:latest";
    extraOptions = [ "--network=host" "--privileged" ];
    volumes = [ "/data/homebridge:/homebridge" ];
  };

  # Homebridge Config UI (8581), main HAP bridge (51167), kasa-python sub-bridge TCP ports
  networking.firewall.allowedTCPPorts = [ 8581 51167 5530 53707 ];
  networking.firewall.allowedUDPPorts = [ 51167 ];
  networking.firewall.allowedUDPPortRanges = [{ from = 5001; to = 65535; }];
}
