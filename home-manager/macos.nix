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

  # JetBrains Toolbox CLI scripts (Toolbox writes this to ~/.zprofile itself,
  # which clobbers the home-manager managed file; keep it here instead)
  programs.zsh.profileExtra = ''
    export PATH="$PATH:${config.home.homeDirectory}/Library/Application Support/JetBrains/Toolbox/scripts"
  '';
}
