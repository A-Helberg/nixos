{ config, pkgs, lib, ... }:
{
  imports = [
    ./common/base.nix
    ./common/macos-defaults.nix
  ];

  # base.nix hardcodes andre; mkForce needed to override it for this user
  home.username = lib.mkForce "agent";
  home.homeDirectory = "/Users/agent";

  programs.zsh.sessionVariables = {
    FLAKE = "/Users/andre/nixos";
    NH_FLAKE = "/Users/andre/nixos";
  };
}
