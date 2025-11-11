{ config, pkgs, inputs, ... }:
{
  imports = [
    ../../darwin
  ];

  networking.hostName = "phoenix";
  system.primaryUser = "andre";

  # Phoenix uses VirtualBox and Aerospace instead of defaults
  homebrew.casks = [
    "virtualbox"
    "nikitabobko/tap/aerospace"
  ];

  system.defaults.dock.persistent-apps = [
    "/Applications/Ghostty.app"
  ];

  system.activationScripts.postUserActivation.text = ''
    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
  '';
}
