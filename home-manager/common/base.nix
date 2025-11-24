{ pkgs, ... }:
{
  home.username = "andre";
  home.stateVersion = "24.05";
  nixpkgs.config.allowUnfree = true;

  catppuccin.enable = true;
  catppuccin.flavor = "mocha";

  imports = [
    ../../programs/neovim
    ../../programs/zsh
    ../../programs/starship
    ../../programs/wezterm
    ../../programs/tmux
    ./modern-cli.nix
    ./developer.nix
  ];

  programs.home-manager.enable = true;
}

