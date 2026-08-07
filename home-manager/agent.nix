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

  # let andre ssh in as agent; the store symlink is root-owned which
  # sshd's StrictModes accepts
  home.file.".ssh/authorized_keys".text = ''
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGLlNhvRxSPN9zNLcPTSL9TbTiqIo+pscmbtL1xAI8uN andre
  '';

  programs.zsh.sessionVariables = {
    FLAKE = "/Users/andre/nixos";
    NH_FLAKE = "/Users/andre/nixos";
  };
}
