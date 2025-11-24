{ config, pkgs, ... }:
{
  imports = [
    ./common/base.nix
  ];

  home.homeDirectory = "/Users/andre";

  programs.zsh.sessionVariables = {
    FLAKE = "/Users/andre/nixos";
    NH_FLAKE = "/Users/andre/nixos";
  };
}
