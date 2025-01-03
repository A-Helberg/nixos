{ pkgs, config, lib, ... }:
let
in
{
  home.packages = [
    pkgs.tmux
  ];

# Managed by stow
#  xdg.configFile."tmux" = {
#    source = ./.config/tmux;
#    recursive = true;
#  };
}
