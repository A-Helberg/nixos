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
  networking.hostName = "phoenix"; # Define your hostname.
  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  system.primaryUser = "andre";

  environment.systemPackages =
    [ 
      pkgs.mkalias
      pkgs.obsidian
      pkgs.tmux
      pkgs.wezterm
      pkgs.nh
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
      "jetbrains-toolbox"
      "choosy"
      "leader-key"
      "hammerspoon"
      "firefox"
      "chromium"
      "iina"
      "the-unarchiver"
      "1Password"
      "docker"
      "virtualbox"
      "arc"
      "nikitabobko/tap/aerospace"
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
  nix.extraOptions = ''
    auto-optimise-store = true
    experimental-features = nix-command flakes
    extra-platforms = x86_64-darwin aarch64-darwin
  '';

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



  # doesn't seem to work
  #      system.activationScripts.enableFileSharing = pkgs.lib.mkForce ''
  #        # Add a shared directory (e.g., /Users/Shared)
  #        #sudo sharing -a /Users/Shared
  #
  #        # Attempt to enable the SMB service
  #        #sudo launchctl enable system/com.apple.smbd
  #        #sudo launchctl kickstart -k system/com.apple.smbd
  #        sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.smbd.plist
  #      '';


      # Auto upgrade nix package and the daemon service.
      services = {
        tailscale.enable = true;
      };
      # nix.package = pkgs.nix;

      # Necessary for using flakes on this system.
      nix.settings.experimental-features = "nix-command flakes";

      # Set Git commit hash for darwin-version.
      # system.configurationRevision = self.rev or self.dirtyRev or null;

      # Used for backwards compatibility, please read the changelog before changing.
      # $ darwin-rebuild changelog
      system.stateVersion = 5;

      # The platform the configuration will be used on.
      nixpkgs.hostPlatform = "aarch64-darwin";

    system.activationScripts.postUserActivation.text = ''
      # Following line should allow us to avoid a logout/login cycle
      /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
    '';

     system.defaults = {
        trackpad.TrackpadThreeFingerDrag = true;
        trackpad.Clicking = true;
        trackpad.TrackpadRightClick = true;

        # Do not automatically re-arrange spaces to most recent
        dock = {
          mru-spaces = false;
          autohide  = true;
          largesize = 64;
          persistent-apps = [
            "/Applications/Ghostty.app"
          #  "${pkgs.alacritty}/Applications/Alacritty.app"
          #  "/Applications/Firefox.app"
          #  "${pkgs.obsidian}/Applications/Obsidian.app"
          #  "/System/Applications/Mail.app"
          #  "/System/Applications/Calendar.app"
          ];
        };

        #finder.FXPreferredViewStyle = "clmv";
        loginwindow.GuestEnabled  = false;
        NSGlobalDomain.AppleICUForce24HourTime = true;
        #NSGlobalDomain.AppleInterfaceStyle = "Dark";
        NSGlobalDomain.KeyRepeat = 2;

        CustomUserPreferences = {
          NSGlobalDomain = {
            # Add a context menu item for showing the Web Inspector in web views
            WebKitDeveloperExtras = true;
          };
          "com.apple.finder" = {
            ShowExternalHardDrivesOnDesktop = true;
            ShowHardDrivesOnDesktop = true;
            ShowMountedServersOnDesktop = true;
            ShowRemovableMediaOnDesktop = true;
            _FXSortFoldersFirst = true;
            # When performing a search, search the current folder by default
            FXDefaultSearchScope = "SCcf";
          };
          "com.apple.desktopservices" = {
            # Avoid creating .DS_Store files on network or USB volumes
            DSDontWriteNetworkStores = true;
            DSDontWriteUSBStores = true;
          };
          "com.apple.screensaver" = {
            # Require password immediately after sleep or screen saver begins
            askForPassword = 1;
            askForPasswordDelay = 0;
          };
          "com.apple.screencapture" = {
            location = "~/screenshots";
            type = "png";
          };
         # "com.apple.Safari" = {
         #   # Privacy: don’t send search queries to Apple
         #   UniversalSearchEnabled = false;
         #   SuppressSearchSuggestions = true;
         #   # Press Tab to highlight each item on a web page
         #   WebKitTabToLinksPreferenceKey = true;
         #   ShowFullURLInSmartSearchField = true;
         #   # Prevent Safari from opening ‘safe’ files automatically after downloading
         #   AutoOpenSafeDownloads = false;
         #   ShowFavoritesBar = false;
         #   IncludeInternalDebugMenu = true;
         #   IncludeDevelopMenu = true;
         #   WebKitDeveloperExtrasEnabledPreferenceKey = true;
         #   WebContinuousSpellCheckingEnabled = true;
         #   WebAutomaticSpellingCorrectionEnabled = false;
         #   AutoFillFromAddressBook = false;
         #   AutoFillCreditCardData = false;
         #   AutoFillMiscellaneousForms = false;
         #   WarnAboutFraudulentWebsites = true;
         #   WebKitJavaEnabled = false;
         #   WebKitJavaScriptCanOpenWindowsAutomatically = false;
         #   "com.apple.Safari.ContentPageGroupIdentifier.WebKit2TabsToLinks" = true;
         #   "com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled" = true;
         #   "com.apple.Safari.ContentPageGroupIdentifier.WebKit2BackspaceKeyNavigationEnabled" = false;
         #   "com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaEnabled" = false;
         #   "com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaEnabledForLocalFiles" = false;
         #   "com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaScriptCanOpenWindowsAutomatically" = false;
         # };
        #  "com.apple.mail" = {
        #    # Disable inline attachments (just show the icons)
        #    DisableInlineAttachmentViewing = true;
        #  };
          "com.apple.AdLib" = {
            allowApplePersonalizedAdvertising = false;
          };
          "com.apple.print.PrintingPrefs" = {
            # Automatically quit printer app once the print jobs complete
            "Quit When Finished" = true;
          };
          "com.apple.SoftwareUpdate" = {
            AutomaticCheckEnabled = true;
            # Check for software updates daily, not just once per week
            ScheduleFrequency = 1;
            # Download newly available updates in background
            AutomaticDownload = 1;
            # Install System data files & security updates
            CriticalUpdateInstall = 1;
          };
          "com.apple.TimeMachine".DoNotOfferNewDisksForBackup = true;
          # Prevent Photos from opening automatically when devices are plugged in
          "com.apple.ImageCapture".disableHotPlug = true;
          # Turn on app auto-update
          "com.apple.commerce".AutoUpdate = true;
        };
      };

}
