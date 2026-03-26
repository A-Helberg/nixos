{ config, pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./fireactions.nix
    ./minio.nix
    ./tunnel.nix
    ./apt-cacher.nix
    ./local-proxy.nix
    ./switchbot.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  nix.settings.experimental-features = [ "flakes" "nix-command" ];

  networking.hostName = "hydra";
  networking = {
    networkmanager.enable = false;
    useDHCP = false;
    defaultGateway = "10.253.1.254";
    nameservers = [ "1.1.1.1" ];

    # Ubuntu may expose this NIC as enp0s31f6 or eno1.
    interfaces.eno1 = {
      useDHCP = false;
      ipv4.addresses = [{
        address = "10.253.10.2";
        prefixLength = 16;
      }];
    };
  };

  # Since we use a static IP, we don't need to wait for DHCP leases.
  # Disabling wait-online is the most resilient approach for servers with virtual interfaces/bridges.
  systemd.network.wait-online.enable = false;

  time.timeZone = "Australia/Brisbane";
  i18n.defaultLocale = "en_ZA.UTF-8";

  fileSystems."/data" = {
    device = "/dev/disk/by-label/data";
    fsType = "ext4";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/hydra-secrets 0700 root root -"
    "L+ /home/andre/build-runner-image.sh - - - - /etc/nixos/nixos/hydra/build-runner-image.sh"
  ];

  users.users.andre = {
    isNormalUser = true;
    description = "Andre";
    extraGroups = [ "wheel" "docker" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGLlNhvRxSPN9zNLcPTSL9TbTiqIo+pscmbtL1xAI8uN andre"
    ];
  };

  programs.zsh.enable = true;
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  # Enable Docker for building custom runner images
  virtualisation.docker.enable = true;

  # fireactions secrets are guarded by fireactions-config.service (see fireactions.nix).
  # Skip minio until its credential file is present.
  systemd.services.minio.unitConfig.ConditionPathExists = "/var/lib/hydra-secrets/minio-root";

  environment.systemPackages = with pkgs; [
    curl
    git
    nh
    vim
    containerd # for the ctr command
  ];

  environment.sessionVariables = {
    FLAKE = "/etc/nixos";
    NH_FLAKE = "/etc/nixos";
  };

  system.stateVersion = "23.11";
}
