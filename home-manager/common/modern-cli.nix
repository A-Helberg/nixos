{ pkgs, ... }:
{
  home.packages = with pkgs; [
    bat
    eza
    zoxide
    ripgrep
    fzf
    delta
    duf
    dust
    procs
    bottom
    sd
    tokei
    hyperfine
    jq
    yq-go
    kondo
    htop
    btop
  ];

  programs.bat = {
    enable = true;
  };

  programs.fd = {
    enable = true;
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
    icons = "auto";
  };

  programs.zsh.shellAliases = {
    ls = "eza";
    ll = "eza -l";
    la = "eza -la";
    lt = "eza --tree";
    cat = "bat";
    cd = "z";
    ps = "procs";
    du = "dust";
    df = "duf";
  };

  programs.zsh.initContent = ''
    eval "$(zoxide init zsh)"

    # Dry-run by default; pass --force to actually delete.
    # Sweeps gitignored files in every repo under the given dir, then
    # runs kondo for artifacts gitignore doesn't know about.
    clean-artifacts() {
      local gitflag=-n kondoflag=-n
      if [[ "$1" == "--force" ]]; then
        gitflag=-f
        kondoflag=-a
        shift
      fi
      local root="''${1:-.}"
      fd -HI -t d '^\.git$' "$root" | while read -r gitdir; do
        local repo="''${gitdir:h}"
        echo "== $repo"
        git -C "$repo" clean -dX "$gitflag"
      done
      kondo "$kondoflag" "$root"
    }
  '';
}

