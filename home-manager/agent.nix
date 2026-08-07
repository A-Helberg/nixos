{ config, pkgs, lib, ... }:
{
  imports = [
    ./common/base.nix
    ./common/macos-defaults.nix
  ];

  # base.nix hardcodes andre; mkForce needed to override it for this user
  home.username = lib.mkForce "agent";
  home.homeDirectory = "/Users/agent";

  # compaudit flags completion dirs not owned by agent (andre's nix profile);
  # -i skips the insecure-directories prompt that aborts interactive startup
  programs.zsh.completionInit = "autoload -U compinit && compinit -i";

  # let andre ssh in as agent. Must be a real file, not a home.file store
  # symlink: sshd StrictModes walks the resolved path and rejects it because
  # /nix/store is group-writable (nixbld)
  home.activation.authorizedKeys = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run mkdir -p -m 700 "$HOME/.ssh"
    run install -m 600 ${pkgs.writeText "agent-authorized-keys" ''
      ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGLlNhvRxSPN9zNLcPTSL9TbTiqIo+pscmbtL1xAI8uN andre
    ''} "$HOME/.ssh/authorized_keys"
  '';

  programs.zsh.sessionVariables = {
    FLAKE = "/Users/andre/nixos";
    NH_FLAKE = "/Users/andre/nixos";
  };
}
