{ config, pkgs, ... }:
{
  home.homeDirectory = "/Users/andre";

  programs.zsh = {
    sessionVariables = {
      NH_FLAKE = "nixos";
    };
    shellAliases = {
      ls = "eza";
      ll = "eza -l";
      la = "eza -la";
      lt = "eza --tree";
      cat = "bat";
      cd = "z";
      find = "fd";
      ps = "procs";
      du = "dust";
      df = "duf";
    };
    initExtra = ''
      eval "$(zoxide init zsh)"
    '';
  };

  programs.bat = {
    enable = true;
    config = {
      theme = "catppuccin-mocha";
    };
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.eza = {
    enable = true;
    enableZshIntegration = true;
    git = true;
    icons = true;
  };
}
