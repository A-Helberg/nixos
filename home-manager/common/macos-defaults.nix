{ config, lib, ... }:
let
  # nix-darwin wrote trackpad settings to both domains; mirror that
  trackpad = {
    TrackpadThreeFingerDrag = true;
    Clicking = true;
    TrackpadRightClick = true;
  };

  # same tile structure nix-darwin generates for system.defaults.dock.persistent-apps
  dockApp = path: {
    tile-data.file-data = {
      _CFURLString = "file://" + path;
      _CFURLStringType = 15;
    };
    tile-type = "file-tile";
  };
in
{
  # Per-user macOS preferences. These used to live in nix-darwin's
  # system.defaults, which only applies them to system.primaryUser;
  # every GUI user's home-manager config imports this instead.
  targets.darwin.defaults = {
    "com.apple.AppleMultitouchTrackpad" = trackpad;
    "com.apple.driver.AppleBluetoothMultitouch.trackpad" = trackpad;

    "com.apple.dock" = {
      mru-spaces = false;
      autohide = true;
      largesize = 64;
      persistent-apps = [
        (dockApp "/Applications/Ghostty.app")
      ];
    };

    "com.apple.finder" = {
      AppleShowAllExtensions = true;
      ShowPathbar = true;
      ShowStatusBar = true;
      FXEnableExtensionChangeWarning = false;
      _FXSortFoldersFirst = true;
      ShowExternalHardDrivesOnDesktop = true;
      ShowHardDrivesOnDesktop = true;
      ShowMountedServersOnDesktop = true;
      ShowRemovableMediaOnDesktop = true;
      FXDefaultSearchScope = "SCcf";
    };

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
      WebKitDeveloperExtras = true;
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
      # Must be absolute: screencapture does not expand "~" and silently
      # falls back to the Desktop when the path is invalid.
      location = "${config.home.homeDirectory}/Screenshots";
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

  # screencapture needs the dir to exist; reload SystemUIServer so the
  # location change takes effect without a re-login
  home.activation.screenshotsDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "${config.home.homeDirectory}/Screenshots"
    run /usr/bin/killall SystemUIServer 2>/dev/null || true
  '';
}
