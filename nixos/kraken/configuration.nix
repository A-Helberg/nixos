# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, pkgs-bleeding, ... }:
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  nix.settings.experimental-features = [ "flakes" "nix-command" ];

  # Bootloader.
  #boot.loader.systemd-boot.enable = true;
  #boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "kraken"; # Define your hostname.
  services.hardware.bolt.enable = true;

  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking = {
    networkmanager.enable = true;
    nftables.enable = true;

    extraHosts = "127.0.0.1 pve";

    firewall = {
      enable = true;

      allowedTCPPorts = [ ];
      extraInputRules = ''
        # allow from docker nets to host
        ip saddr 172.0.0.0/8 accept
      '';
    };

  };

  # Set your time zone.
  time.timeZone = "Africa/Johannesburg";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_ZA.UTF-8";


  # Enable the X11 windowing system.
  services.xserver.enable = true;
  services.xserver.displayManager.autoLogin.enable = true;
  services.xserver.displayManager.autoLogin.user = "andre";

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.displayManager.gdm.autoSuspend = false;
  services.xserver.displayManager.gdm.wayland = true;
  ## run `dconf write /org/gnome/mutter/experimental-features "['scale-monitor-framebuffer']"` to allow fractional scaling
  services.xserver.desktopManager.gnome = {
    enable = true;
  };


  # Gaming
  hardware.opengl = {
    enable = true;
    #driSupport = true;
    driSupport32Bit = true;
  };
  services.xserver.videoDrivers = ["amdgpu"];

  #fonts.optimizeForVeryHighDpi = true;
  fonts.fontconfig.antialias = true;
  fonts.packages = with pkgs; [
    # https://nixos.wiki/wiki/Fonts
    (nerdfonts.override { fonts = [ "FiraCode" "SourceCodePro" ]; })
    fira
    fira-code
    roboto
    libertine
    source-serif-pro
    stix-two
    vistafonts
  ];

  # Configure keymap in X11
  services.xserver = {
    layout = "us";
    xkbVariant = "";
    dpi = 140;
  };

  # Virtualisation
  boot.binfmt.emulatedSystems = ["aarch64-linux"];
  boot.binfmt.preferStaticEmulators = true;
  virtualisation.docker.enable = true;
  virtualisation.docker.daemon.settings = {features = {
    containerd-snapshotter = true;
  };};
  virtualisation.virtualbox.host.enable = true;
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
      ovmf = {
        enable = true;
        packages = [(pkgs.OVMF.override {
          secureBoot = true;
          tpmSupport = true;
        }).fd];
      };
    };
  };

  # Enable CUPS to print documents.
  services.printing.enable = false;

  # Enable sound with pipewire.
  #sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  # FIDO device support
  security.pam.u2f.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.andre = {
    isNormalUser = true;
    description = "Andre";
    extraGroups = [ "networkmanager" "wheel" "docker" "libvirtd" "ubridge" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGLlNhvRxSPN9zNLcPTSL9TbTiqIo+pscmbtL1xAI8uN andre"];
    packages = with pkgs; [
    #  thunderbird
    ];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Install Programs.
  programs.firefox.enable = true;
  programs.nix-ld.enable = true;
  programs.zsh.enable = true;
  services.tailscale.enable = true;
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    # Certain features, including CLI integration and system authentication support,
    # require enabling PolKit integration on some desktop environments (e.g. Plasma).
    polkitPolicyOwners = [ "andre" ];
  };

  environment.sessionVariables  = {
    # So that we don't have to specify this to nh os switch
    FLAKE = "/etc/nixos";
    NH_FLAKE = "/etc/nixos";
  };


  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    #  vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    #  wget
    mergerfs
    pkgs-bleeding.docker
    pkgs-bleeding.docker-compose

    # we need git to install our dotfiles & home-mnager configs
    git

    # run https://github.com/pop-os/shell/blob/master_jammy/scripts/configure.sh for shortcuts
    gnomeExtensions.pop-shell
    curl
    #aria2c
    qemu
    vim
    # GNS3
    gns3-server
    ubridge
    virt-viewer
    spice
    tigervnc
    inetutils

    docker
    zlib
    openssl

    # gaming
    protonup
    lutris
    bottles


    # nixos helper
    nh
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  services.gns3-server.ubridge.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?



  # overlay fs to allow commands like docker to be run form macos
  # Paths will be the Same on poth so $PWD can be used to mount volumes

  # the lowerdir is /mnt/remote/Users in which we symlink to the cifs mount /mnt/remote/mac
  # /mnt/remote/mac is a cifs mount to the Users home directory on the mac
  # we use an overlay fs so that files written on linux do not clobber the mac's version
  systemd.tmpfiles.rules = [
    "d /Users 0755 andre andre"

    "d /mnt/remote 0755 andre andre"
    "d /mnt/remote/Users 0755 andre andre"
    "d /mnt/remote/Users/andre 0755 andre andre"

    "d /mnt/remote/workdir 0755 andre andre"
    "d /mnt/remote/upperdir 0755 andre andre"

    "d /mnt/merger/Users 0755 andre andre"
  ];

  #system.userActivationScripts.linktosharedfolder.text = ''
  #  if [[ ! -h "/mnt/remote/Users/andre/Projects" ]]; then
  #    ln -s "/mnt/remote/mac/" "/mnt/remote/Users/andre/Projects"
  #  fi
  #'';

  fileSystems."/mnt/remote/Users/andre/Projects" = {
    device = "//10.253.0.2/Projects";       # Replace with your server and share path
    fsType = "cifs";                    # Filesystem type
    options = [
      "rw"                              # Read-write access
      "uid=1000"                        # Replace 1000 with the UID of the specific user
      "gid=100"                        # Replace 1000 with the GID of the specific user
      "credentials=/home/andre/.cifs-creds" # Path to credentials file
      "vers=3.0"                        # SMB version (adjust if needed)
      "soft"
      "rw"
    ];
    neededForBoot = false; # Ensure it’s not mounted at boot automatically
  };

  fileSystems."/mnt/merger/Users" = {
    depends = ["/mnt/remote/Users/andre/Projects"];
    device = "/mnt/remote/Users";
    fsType = "mergerfs";                    # Filesystem type
    neededForBoot = false; # Ensure it’s not mounted at boot automatically
  };


  fileSystems."/Users" = {
    device = "overlay";
    fsType = "overlay";                    # Filesystem type
    depends = ["/mnt/merger/Users"];
    neededForBoot = false; # Ensure it’s not mounted at boot automatically
    options = [
      "lowerdir=/mnt/merger/Users"
      "upperdir=/mnt/remote/upperdir"
      "workdir=/mnt/remote/workdir"
    ];
  };


}
