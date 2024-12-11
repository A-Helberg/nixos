{ pkgs, config, lib, ... }:
let
in
{
  home.packages = [
  ];

  programs.wezterm = {
    enable = true;

    # makes the prompt faster
    enableZshIntegration = false;

    extraConfig = ''
      require "lua/config"
      return config()
    '';
  };

  xdg.configFile."wezterm/lua" = {
    source = ./.config/wezterm/lua;
    recursive = true;
  };
}
