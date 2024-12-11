{ pkgs, pkgs-stable, config, lib, ... }:
let
in
{
  home.packages = [
    pkgs.starship
  ];

  programs.starship = {
  };

  xdg.configFile."starship.toml" = {
    source = ./.config/starship.toml;
    recursive = true;
  };
}
