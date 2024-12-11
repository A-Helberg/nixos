{ pkgs, pkgs-stable, config, lib, ... }:
let
in
{
  home.packages = [
  ];

  programs.zsh = {
    enable = true;
    initExtra = ''
      source ~/.config/zsh/zshrc
    '';
  };

  xdg.configFile."zsh/zshrc" = {
    source = ./.config/zshrc;
    recursive = true;
  };
}
