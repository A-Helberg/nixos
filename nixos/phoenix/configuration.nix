{ config, pkgs, inputs, ... }:
{
  imports = [
    ../../darwin
  ];

  networking.hostName = "phoenix";
  system.primaryUser = "andre";

  services.openssh.enable = true;

  # macOS gates ssh logins on com.apple.access_ssh membership; agent is not
  # an admin so it must be added explicitly (idempotent)
  system.activationScripts.postActivation.text = ''
    dseditgroup -o edit -a agent -t user com.apple.access_ssh 2>/dev/null || true
  '';

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
}
