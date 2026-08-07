{ pkgs, ... }:
{
  hardware.bluetooth.enable = true;

  systemd.tmpfiles.rules = [
    "d /data/homebridge 0700 root root -"
  ];

  system.activationScripts.homebridge-plugin-setup = {
    text = ''
      # Stage our local plugin on the persisted volume. It must NOT be
      # copied straight into node_modules from here: hb-service/npm
      # prunes hand-copied packages on container boot, which is how the
      # lock integration once vanished after a container restart.
      # startup.sh (below) re-installs it inside the container on every
      # boot, after hb-service has run.
      mkdir -p /data/homebridge/plugin-src/homebridge-switchbot-lock-ultra
      cp ${./homebridge-switchbot-lock-ultra/package.json} /data/homebridge/plugin-src/homebridge-switchbot-lock-ultra/package.json
      cp ${./homebridge-switchbot-lock-ultra/index.js}     /data/homebridge/plugin-src/homebridge-switchbot-lock-ultra/index.js

      cat > /data/homebridge/startup.sh << 'EOF'
#!/bin/bash
# Install kasa plugin (needs hb-service from inside the container)
hb-service add homebridge-kasa-python 2>/dev/null || true

# (Re-)install our local plugin after hb-service/npm may have pruned it
mkdir -p /homebridge/node_modules/homebridge-switchbot-lock-ultra
cp /homebridge/plugin-src/homebridge-switchbot-lock-ultra/* /homebridge/node_modules/homebridge-switchbot-lock-ultra/
EOF
      chmod +x /data/homebridge/startup.sh
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
