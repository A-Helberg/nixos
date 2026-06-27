{ pkgs, config, lib, ... }:
let
in
{
  home.packages = [
  ];

  programs.zsh = {
    enable = true;

    shellAliases = {
      nps = "cat package.json | jq .scripts";
    };

    initContent = ''
      source ~/.config/zsh/zshrc
    '';
  };

  # Managed by stow
  #xdg.configFile."zsh/zshrc" = {
  #  source = ./.config/zshrc;
  #  recursive = true;
  #};
}

# Debugging

# ```
# zmodload zsh/zprof
# zprof
# ```
