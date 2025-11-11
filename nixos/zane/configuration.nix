{config, pkgs, inputs, ...}:
{
  imports = [
    # If you want to use modules your own flake exports (from modules/darwin):
    # inputs.self.darwinModules.example

    # Or modules from other flakes (such as nixos-hardware):
    # inputs.hardware.nixosModules.common-cpu-amd
    # inputs.hardware.nixosModules.common-ssd

    # You can also split up your configuration and import pieces of it here:
    # ./users.nix
    # ./common/yabai.nix
    # ./common/skhd.nix
    # ./common/sketchybar.nix
    # ./common/aerospace.nix
  ];
  nix.enable = false;
  networking.hostName = "Zanes-MacBook-Air-2"; # Define your hostname.
  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  system.primaryUser = "andre";

  environment.systemPackages = with pkgs; [
    mkalias
    obsidian
    tmux
    wezterm
    nh
    
    # Modern CLI replacements
    bat
    eza
    zoxide
    fd
    ripgrep
    fzf
    jq
    yq-go
    delta
    duf
    dust
    procs
    bottom
    sd
    tokei
    hyperfine
    
    # Network tools
    curl
    wget
    
    # Dev tools
    tree-sitter
  ];

  homebrew = {
    enable = true;
    brews = [
      "mas"
      "tailscale"
      "iproute2mac"
      "llama.cpp"
      "btop"
      "websocat"
    ];
    casks = [
      "karabiner-elements"
      "jetbrains-toolbox"
      "choosy"
      "leader-key"
      "hammerspoon"
      "firefox"
      "chromium"
      "iina"
      "the-unarchiver"
      "1Password"
      "orbstack"
      "arc"
      #"nikitabobko/tap"
      #"nikitabobko/tap/aerospace"
      "little-snitch"
      "ghostty"
      "raycast"
      "visual-studio-code"
    ];
    masApps = {
      "Slack" = 803453959;
      "1PasswordSafari" = 1569813296;
      "Amphetamine" = 937984704;
    };
    onActivation.cleanup = "zap";
  };

  nix = {
    extraOptions = ''
      auto-optimise-store = true
      experimental-features = nix-command flakes
      extra-platforms = x86_64-darwin aarch64-darwin
    '';
    settings.experimental-features = "nix-command flakes";
  };

    #programs.nh = {
        #enable = true;
    #    clean.enable = true;
    #    # Installation option once https://github.com/LnL7/nix-darwin/pull/942 is merged:
    #    #package = inputs.nh_darwin.packages.${pkgs.stdenv.hostPlatform.system}.default;
    #    os.flake = "/Users/andre/nixos";
    #    home.flake = "/Users/andre/nixos";
    #};

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
      while read -r src; do
        app_name=$(basename "$src")
        echo "copying $src" >&2
        ${pkgs.mkalias}/bin/mkalias "$src" "/Applications/Nix Apps/$app_name"
      done
    '';

  system.stateVersion = 5;
  nixpkgs.hostPlatform = "aarch64-darwin";

  system.defaults = {
    trackpad = {
      TrackpadThreeFingerDrag = true;
      Clicking = true;
      TrackpadRightClick = true;
    };

    dock = {
      mru-spaces = false;
      autohide = true;
      largesize = 64;
      persistent-apps = [
        "/Applications/Ghostty.app"
      ];
    };

    finder = {
      AppleShowAllExtensions = true;
      ShowPathbar = true;
      ShowStatusBar = true;
      FXEnableExtensionChangeWarning = false;
      _FXSortFoldersFirst = true;
    };

    loginwindow.GuestEnabled = false;
    
    NSGlobalDomain = {
      AppleICUForce24HourTime = true;
      KeyRepeat = 2;
      InitialKeyRepeat = 15;
      ApplePressAndHoldEnabled = false;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
    };

    CustomUserPreferences = {
      NSGlobalDomain.WebKitDeveloperExtras = true;
      
      "com.apple.finder" = {
        ShowExternalHardDrivesOnDesktop = true;
        ShowHardDrivesOnDesktop = true;
        ShowMountedServersOnDesktop = true;
        ShowRemovableMediaOnDesktop = true;
        _FXSortFoldersFirst = true;
        FXDefaultSearchScope = "SCcf";
      };
      
      "com.apple.desktopservices" = {
        DSDontWriteNetworkStores = true;
        DSDontWriteUSBStores = true;
      };
      
      "com.apple.screensaver" = {
        askForPassword = 1;
        askForPasswordDelay = 0;
      };
      
      "com.apple.screencapture" = {
        location = "~/screenshots";
        type = "png";
      };
      
      "com.apple.AdLib".allowApplePersonalizedAdvertising = false;
      "com.apple.print.PrintingPrefs"."Quit When Finished" = true;
      
      "com.apple.SoftwareUpdate" = {
        AutomaticCheckEnabled = true;
        ScheduleFrequency = 1;
        AutomaticDownload = 1;
        CriticalUpdateInstall = 1;
      };
      
      "com.apple.TimeMachine".DoNotOfferNewDisksForBackup = true;
      "com.apple.ImageCapture".disableHotPlug = true;
      "com.apple.commerce".AutoUpdate = true;
    };
  };
}
