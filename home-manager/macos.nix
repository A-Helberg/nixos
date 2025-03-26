{ config, pkgs, ... }:
{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.homeDirectory = "/Users/andre";

  programs.zsh.sessionVariables = {
    NH_FLAKE="nixos";
  };

}
