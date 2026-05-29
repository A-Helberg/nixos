{ config, pkgs, inputs, ... }:
{
  imports = [
    ../../darwin
  ];

  networking.hostName = "phoenix";
  system.primaryUser = "andre";

  # Phoenix uses Parallels in addition to shared defaults
  homebrew.casks = [
    "parallels"
  ];

  homebrew.taps = [ "jank-lang/jank" ];
  homebrew.brews = [ "jank-lang/jank/jank" ];

  system.defaults.dock.persistent-apps = [
    { app = "/Applications/Ghostty.app"; }
  ];

  system.activationScripts.postActivation.text = ''
    sudo -u andre /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
  '';
}
