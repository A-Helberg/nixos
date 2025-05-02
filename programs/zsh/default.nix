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

    initExtra = ''
      source ~/.config/zsh/zshrc
      export ASDF_FORCE_PREPEND="no"
      export PATH="$PATH:$HOME/.asdf/shims:$HOME/.asdf/bin"
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
