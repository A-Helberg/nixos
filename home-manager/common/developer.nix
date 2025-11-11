{ pkgs, ... }:
{
  home.packages = with pkgs; [
    git
    curl
    wget
    starship
    stow
    go-task
    kubectl
    mtr
    iperf3
    killall
    nerd-fonts.jetbrains-mono
  ];

  programs.git = {
    enable = true;
    userName = "Andre Helberg";
    userEmail = "helberg.andre@gmail.com";
    ignores = [
      ".DS_Store"
      ".idea"
    ];
    extraConfig = {
      init.defaultBranch = "main";
    };
  };

  programs.zsh = {
    enable = true;
    sessionVariables = {
      EDITOR = "nvim";
    };
  };
}
