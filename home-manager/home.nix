{ config, pkgs, catppuccin, ... }:
{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "andre";
  nixpkgs.config.allowUnfree = true;

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "24.05"; # Please read the comment before changing.


  # COLORS!!!
  catppuccin.enable = true;
  catppuccin.flavor = "mocha";

  # The home.packages option allows you to install Nix packages into your
  # environment.

  programs.zsh = {
    enable = true;
    shellAliases = {
      rrun = ''f() { ssh 10.253.0.1 tmux new -d -s remote 2>/dev/null || true;
                      ssh 10.253.0.1 tmux send-keys -t remote.0 "'cd $PWD && clear'" ENTER "'$*'" ENTER "'read -s -k \"?Press any key to continue.\" && tmux detach'" ENTER
                      ssh -tt 10.253.0.1 tmux attach -t remote.0 };f'';
    };

    sessionVariables = {
      EDITOR = "nvim";
    };
  };

  home.packages = [
    pkgs.htop
    pkgs.stow

    # git tools
    pkgs.git
    pkgs.gitui

    # potentially used for port forwarding & dev domains
    pkgs.caddy



    pkgs.obsidian


    pkgs.realvnc-vnc-viewer
    # network tools
    pkgs.mtr
    pkgs.iperf3

    #pkgs.appimage-run

    ## terminal utils
    pkgs.stow
    pkgs.ripgrep
    pkgs.starship
    pkgs.eza
    pkgs.bat
    pkgs.slack
    #pkgs-stable.ncdu
    pkgs.killall



    # move to dev-shell
    #(pkgs.callPackage ./hv.nix {})
    #(pkgs.callPackage ./nomad-pack.nix {})

    ## Dev
    # all of these can be put in dev-shells
    #pkgs.oauth2c
    #pkgs.gnumake
    #pkgs.rustc
    #pkgs.gcc
    #pkgs.cargo
    #pkgs.packer
    #pkgs.nomad
    #pkgs.jq
    #pkgs.sshpass
    #pkgs.websocat
    #pkgs.terraform

    ##pkgs.asdf-vm

    # I use clojure nough to have it globally available
    pkgs.rlwrap
    pkgs.clojure

    # # Adds the 'hello' command to your environment. It prints a friendly
    # # "Hello, world!" when run.
    # pkgs.hello

    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    #(pkgs.nerdfonts.override { fonts = [ "JetBrainsMono" ]; })
    pkgs.nerd-fonts.jetbrains-mono

    # # You can also create simple shell scripts directly inside your
    # # configuration. For example, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')
  ];



  imports = [
    ../programs/neovim
    ../programs/zsh
    ../programs/starship
    ../programs/wezterm
    ../programs/tmux
  ];

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';
  };

  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. These will be explicitly sourced when using a
  # shell provided by Home Manager. If you don't want to manage your shell
  # through Home Manager then you have to manually source 'hm-session-vars.sh'
  # located at either
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  ~/.local/state/nix/profiles/profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/andre/etc/profile.d/hm-session-vars.sh
  #

  programs.git = {
    enable = true;
    userName = "Andre Helberg";
    userEmail = "helberg.andre@gmail.com";
    ignores = [
       ".DS_Store"
       ".idea"
    ];
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

}
