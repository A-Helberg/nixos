{ config, pkgs, inputs, ... }:
{
  imports = [
    ../../darwin
  ];

  networking.hostName = "phoenix";
  system.primaryUser = "andre";

  # nix-darwin only manages users listed in knownUsers; agent is created on activation
  users.knownUsers = [ "agent" ];
  users.users.agent = {
    uid = 503;
    description = "Agent";
    home = "/Users/agent";
    createHome = true;
    shell = pkgs.zsh;
  };

  # Phoenix uses Parallels in addition to shared defaults
  homebrew.casks = [
    "parallels"
  ];

  homebrew.taps = [ "jank-lang/jank" ];
  homebrew.brews = [ "jank-lang/jank/jank" ];

  system.activationScripts.postActivation.text = ''
    sudo -u andre /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
  '';
}
