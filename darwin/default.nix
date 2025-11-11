{ config, pkgs, ... }:
{
  system.stateVersion = 5;
  nixpkgs.hostPlatform = "aarch64-darwin";

  # Let Determinate Nix manage the daemon
  nix.enable = false;
  
  nix = {
    extraOptions = ''
      auto-optimise-store = true
      experimental-features = nix-command flakes
      extra-platforms = x86_64-darwin aarch64-darwin
    '';
    settings.experimental-features = "nix-command flakes";
  };

  system.activationScripts.applications.text = let
    env = pkgs.buildEnv {
      name = "system-applications";
      paths = config.environment.systemPackages;
      pathsToLink = "/Applications";
    };
  in pkgs.lib.mkForce ''
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

  environment.systemPackages = with pkgs; [
    mkalias
    nh
  ];

  homebrew = {
    enable = true;
    onActivation.cleanup = "zap";

    brews = [
      "mas"
      "tailscale"
      "iproute2mac"
      "websocat"
      "llama.cpp"
    ];

    casks = [
      # Development
      "jetbrains-toolbox"
      "visual-studio-code"
      "orbstack"
      "ghostty"
      
      # Browsers
      "firefox"
      "chromium"
      "arc"
      "choosy"
      
      # Productivity
      "1password"
      "obsidian"
      "iina"
      "the-unarchiver"
      
      # Power User
      "karabiner-elements"
      "leader-key"
      "hammerspoon"
      "raycast"
      
      # Security
      "little-snitch"
    ];

    masApps = {
      "Slack" = 803453959;
      "1Password for Safari" = 1569813296;
      "Amphetamine" = 937984704;
    };
  };
}

