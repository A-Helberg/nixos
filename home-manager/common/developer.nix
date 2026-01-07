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
    ignores = [
      ".DS_Store"
      ".idea"
    ];
    settings = {
      user = {
        name = "Andre Helberg";
        email = "helberg.andre@gmail.com";
      };
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
