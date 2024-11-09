{config, pkgs, inputs, ...}:
{
  imports = [
    # If you want to use modules your own flake exports (from modules/darwin):
    # inputs.self.darwinModules.example

    # Or modules from other flakes (such as nixos-hardware):
    # inputs.hardware.nixosModules.common-cpu-amd
    # inputs.hardware.nixosModules.common-ssd
    inputs.nh_darwin.nixDarwinModules.prebuiltin

    # You can also split up your configuration and import pieces of it here:
    # ./users.nix
    # ./common/yabai.nix
    # ./common/skhd.nix
    # ./common/sketchybar.nix
    # ./common/aerospace.nix
  ];
  networking.hostName = "phoenix"; # Define your hostname.
  nixpkgs.config.allowUnfree = true;
# List packages installed in system profile. To search by name, run:
      # $ nix-env -qaP | grep wget
      environment.systemPackages =
        [ 
          pkgs.neovim
          pkgs.mkalias
          pkgs.obsidian
          pkgs.tmux
        ];
       nix.extraOptions = ''
    auto-optimise-store = true
    experimental-features = nix-command flakes
    extra-platforms = x86_64-darwin aarch64-darwin
  '';

      programs.nh = {
        enable = true;
        clean.enable = true;
        # Installation option once https://github.com/LnL7/nix-darwin/pull/942 is merged:
        #package = inputs.nh_darwin.packages.${pkgs.stdenv.hostPlatform.system}.default;
       os.flake = "/Users/andre/nixos";
       home.flake = "/Users/andre/nixos";
      };

      system.activationScripts.applications.text = let
          env = pkgs.buildEnv {
            name = "system-applications";
            paths = config.environment.systemPackages;
            pathsToLink = "/Applications";
          };
        in
          pkgs.lib.mkForce ''
          # Set up applications.
          echo "setting up /Applications..." >&2
          rm -rf /Applications/Nix\ Apps
          mkdir -p /Applications/Nix\ Apps
          find ${env}/Applications -maxdepth 1 -type l -exec readlink '{}' + |
          while read src; do
            app_name=$(basename "$src")
            echo "copying $src" >&2
            ${pkgs.mkalias}/bin/mkalias "$src" "/Applications/Nix Apps/$app_name"
          done
      '';

      homebrew = {
        enable = true;
        brews = [
          "mas"
          "tailscale"
        ];
        casks = [
          "hammerspoon"
          "firefox"
          "iina"
          "the-unarchiver"
          "1Password"
          "kitty"
          "docker"
          "virtualbox"
        ];
        masApps = {
          "Slack" = 803453959;
          "1PasswordSafari" = 1569813296;
          "Amphetamine" = 937984704;
        };
        onActivation.cleanup = "zap";
      };

      # Auto upgrade nix package and the daemon service.
      services = {
        nix-daemon.enable = true;
        tailscale.enable = true;
      };
      # nix.package = pkgs.nix;

      # Necessary for using flakes on this system.
      nix.settings.experimental-features = "nix-command flakes";

      # Enable alternative shell support in nix-darwin.
      # programs.fish.enable = true;

      # Set Git commit hash for darwin-version.
      # system.configurationRevision = self.rev or self.dirtyRev or null;

      # Used for backwards compatibility, please read the changelog before changing.
      # $ darwin-rebuild changelog
      system.stateVersion = 5;

      # The platform the configuration will be used on.
      nixpkgs.hostPlatform = "x86_64-darwin";

     system.defaults = {
        trackpad.TrackpadThreeFingerDrag = true;
        trackpad.Clicking = true;
        trackpad.TrackpadRightClick = true;


        #dock.autohide  = true;
        #dock.largesize = 64;
        #dock.persistent-apps = [
        #  "${pkgs.alacritty}/Applications/Alacritty.app"
        #  "/Applications/Firefox.app"
        #  "${pkgs.obsidian}/Applications/Obsidian.app"
        #  "/System/Applications/Mail.app"
        #  "/System/Applications/Calendar.app"
        #];
        #finder.FXPreferredViewStyle = "clmv";
        loginwindow.GuestEnabled  = false;
        NSGlobalDomain.AppleICUForce24HourTime = true;
        #NSGlobalDomain.AppleInterfaceStyle = "Dark";
        NSGlobalDomain.KeyRepeat = 2;
      };
}
