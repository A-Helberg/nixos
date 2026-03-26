# fireactions v2.x service for hydra.
#
# Uses microvm-base for shared infrastructure (containerd, CNI, bridge, kernel)
# and runs fireactions server with native v2.x YAML config.
#
# The config is generated at build time with placeholder secrets, then a
# preStart script injects the GitHub App credentials from secret files.
{ inputs, pkgs, config, lib, ... }:

let
  fireactionsPkg = pkgs.callPackage ./fireactions-package.nix { };

  # Kernel path from microvm-base (shared infrastructure).
  kernelPath = config.services.microvm-base._internal.kernelPath;
  kernelArgs = config.services.microvm-base._internal.kernelArgs;

  # Base config — secrets are injected at runtime by the preStart script.
  # Secrets placeholders use @@ markers replaced by sed.
  baseConfig = pkgs.writeText "fireactions-base.yaml" ''
    bind_address: "0.0.0.0:8080"

    metrics:
      enabled: true
      address: "127.0.0.1:8081"

    github:
      app_id: @@GITHUB_APP_ID@@
      app_private_key: |
        @@GITHUB_APP_PRIVATE_KEY@@

    pools:
      - name: Default
        replicas: 1
        max_replicas: 3
        shutdown_on_exit: true
        runner:
          name: Default
          image: "ghcr.io/hostinger/fireactions-images/ubuntu24.04:latest"
          image_pull_policy: IfNotPresent
          group_id: 1
          organization: iConceptLogistics
          labels:
            - self-hosted
            - fireactions
            - linux
            - hydra
        firecracker:
          binary_path: "${pkgs.firecracker}/bin/firecracker"
          kernel_image_path: "${kernelPath}"
          kernel_args: "${kernelArgs}"
          machine_config:
            mem_size_mib: 8192
            vcpu_count: 2
  '';

  # Script that injects secrets into the config at runtime.
  configScript = pkgs.writeShellScript "fireactions-config" ''
    set -euo pipefail

    APP_ID_FILE="/var/lib/hydra-secrets/github-app-id"
    KEY_FILE="/var/lib/hydra-secrets/github-app-key"

    for f in "$APP_ID_FILE" "$KEY_FILE"; do
      if [ ! -f "$f" ]; then
        echo "ERROR: secret file not found: $f"
        exit 1
      fi
    done

    APP_ID=$(cat "$APP_ID_FILE")
    # Indent the private key for YAML block scalar (4 spaces after the leading line)
    PRIVATE_KEY=$(sed 's/^/        /' "$KEY_FILE")

    mkdir -p /run/fireactions
    sed \
      -e "s|@@GITHUB_APP_ID@@|$APP_ID|g" \
      -e "/@@GITHUB_APP_PRIVATE_KEY@@/ {
        r /dev/stdin
        d
      }" ${baseConfig} <<< "$PRIVATE_KEY" \
      > /run/fireactions/config.yaml

    chmod 0600 /run/fireactions/config.yaml
  '';

in
{
  imports = [
    inputs.nixos-fireactions.nixosModules.microvm-base
  ];

  # Register the fireactions bridge with the shared infrastructure.
  services.microvm-base = {
    enable = true;
    bridges.fireactions = {
      bridgeName = "fireactions0";
      subnet = "10.200.0.0/24";
      externalInterface = "eno1";
    };
  };

  # CNI config for fireactions bridge (required by firecracker-go-sdk).
  environment.etc."cni/net.d/fireactions.conflist".text = builtins.toJSON {
    cniVersion = "1.0.0";
    name = "fireactions";
    plugins = [
      {
        type = "bridge";
        bridge = "fireactions0";
        isGateway = true;
        ipMasq = true;
        ipam = {
          type = "host-local";
          subnet = "10.200.0.0/24";
          routes = [{ dst = "0.0.0.0/0"; }];
        };
        dns = {
          nameservers = [ "10.200.0.1" ];
        };
      }
      { type = "firewall"; }
      { type = "tc-redirect-tap"; }
    ];
  };

  environment.systemPackages = [ fireactionsPkg ];

  systemd.tmpfiles.rules = [
    "d /var/lib/fireactions 0750 root root -"
    "d /var/lib/fireactions/pools 0750 root root -"
    "d /run/fireactions 0750 root root -"
    # Clean up stale sockets from VMs that didn't shut down cleanly.
    "r /var/lib/fireactions/pools/*/*.sock - - - - -"
  ];

  # Inject secrets and write the runtime config.
  systemd.services.fireactions-config = {
    description = "Prepare fireactions config with secrets";
    wantedBy = [ "fireactions.service" ];
    before = [ "fireactions.service" ];
    requiredBy = [ "fireactions.service" ];
    unitConfig.ConditionPathExists = [
      "/var/lib/hydra-secrets/github-app-id"
      "/var/lib/hydra-secrets/github-app-key"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${configScript}";
    };
  };

  systemd.services.fireactions = {
    description = "Fireactions - GitHub Actions runner manager";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "containerd.service"
      "fireactions-config.service"
    ];
    requires = [
      "containerd.service"
      "fireactions-config.service"
    ];
    wants = [ "network-online.target" ];

    path = [
      pkgs.firecracker
      pkgs.containerd
      pkgs.runc
      pkgs.cni-plugins
      pkgs.iptables
      pkgs.iproute2
    ];

    environment = {
      CNI_PATH = lib.makeBinPath [
        pkgs.cni-plugins
        config.services.microvm-base._internal.tcRedirectTapPkg
      ];
      NETCONFPATH = "/etc/cni/net.d";
    };

    serviceConfig = {
      Type = "simple";
      ExecStart = "${fireactionsPkg}/bin/fireactions server --config /run/fireactions/config.yaml";
      Restart = "on-failure";
      RestartSec = "5s";
      TimeoutStopSec = "150s";
      WorkingDirectory = "/var/lib/fireactions";
      LimitNOFILE = 65536;
      OOMScoreAdjust = -900;
    };
  };

  # Allow VMs outbound and block VM-to-VM traffic.
  networking.nftables.enable = true;
  networking.nftables.tables.fireactions_isolation = {
    family = "inet";
    content = ''
      chain forward {
        type filter hook forward priority filter; policy accept;
        ct state established,related accept
        iifname "fireactions0" oifname "fireactions0" drop comment "Block VM-to-VM traffic"
        iifname "fireactions0" oifname != "fireactions0" accept
      }
    '';
  };

}
