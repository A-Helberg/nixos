{ pkgs, config, lib, ... }:
let
in
{
  home.packages = [
    pkgs.tmux
  ];

  xdg.configFile."tmux" = {
    source = ./.config/tmux;
    recursive = true;
  };
}
