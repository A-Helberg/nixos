{ pkgs, ... }:
{
  home.packages = with pkgs; [
    bat
    eza
    zoxide
    fd
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
    htop
    btop
  ];

  programs.bat = {
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
    find = "fd";
    ps = "procs";
    du = "dust";
    df = "duf";
  };

  programs.zsh.initExtra = ''
    eval "$(zoxide init zsh)"
  '';
}

