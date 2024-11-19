{ config, pkgs, pkgs-stable, catppuccin, ... }:
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
  #catppuccin.enable = true;
  catppuccin.flavor = "mocha";
  # The home.packages option allows you to install Nix packages into your
  # environment.

  programs.zsh = {
    enable = true;
    # catppuccin.enable = true;
  };

  programs.kitty = pkgs.lib.mkForce {
    enable = true;
    settings = {
      shell = "${pkgs.zsh}/bin/zsh";
    };

  };
  home.packages = [
    pkgs.htop

    # git tools
    pkgs.git
    pkgs.gitui
    pkgs.kitty


    pkgs.obsidian

    pkgs.packer
    pkgs.nomad
    pkgs.sshpass
    pkgs.websocat

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
    pkgs.tmux
    pkgs.slack
    #pkgs-stable.ncdu
    pkgs.killall



    (pkgs.callPackage ./hv.nix {})
    (pkgs.callPackage ./nomad-pack.nix {})

    ## Dev
    pkgs.oauth2c
    pkgs.gnumake
    pkgs.rustc
    pkgs.cargo
    pkgs.jq
    pkgs.gcc

    ##pkgs.asdf-vm

    pkgs.rlwrap
    pkgs.clojure
    pkgs.terraform

    # # Adds the 'hello' command to your environment. It prints a friendly
    # # "Hello, world!" when run.
    # pkgs.hello

    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

    # # You can also create simple shell scripts directly inside your
    # # configuration. For example, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')
  ];

  imports = [
    ./programs/neovim/default.nix
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
  home.sessionVariables = {
    EDITOR = "nvim";
  };

  programs.git = {
    enable = true;
    userName = "Andre Helberg";
    userEmail = "helberg.andre@gmail.com";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

}
