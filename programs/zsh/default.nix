{ pkgs, config, lib, ... }:
let
in
{
  home.packages = [
  ];

  programs.zsh = {
    enable = true;
    initExtra = ''
      source ~/.config/zsh/zshrc
      . "$HOME/.asdf/asdf.sh"
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
