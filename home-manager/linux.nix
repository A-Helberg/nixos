{ config, pkgs, ... }:
{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.homeDirectory = "/home/andre";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "24.05"; # Please read the comment before changing.

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = [

    #pkgs.jetbrains.idea-community-src
    pkgs.gns3-gui
    #pkgs.vagrant
    (pkgs.vagrant.override { withLibvirt = false; })
    pkgs.virt-manager
#    pkgs.kicad

    pkgs.wireshark

    # Apple music on linux
    pkgs.cider

    pkgs.libreoffice

    pkgs.gnomeExtensions.notification-timeout
    pkgs.gnomeExtensions.system-monitor
    pkgs.gnomeExtensions.gsconnect
    pkgs.gnomeExtensions.espresso
    pkgs.gnomeExtensions.notification-banner-position

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

  dconf.settings = {
    "org/gnome/shell" = {
        disable-user-extensions = false;
        disabled-extensions = "disabled";
        enabled-extensions = [
          "pop-shell@system76.com"
          "system-monitor@gnome-shell-extensions.gcampax.github.com"
          "hidetopbar@mathieu.bidon.ca"
          "gsconnect@andyholmes.github.io"
          "espresso@coadmunkee.github.com"
          "gsconnect@andyholmes.github.io"
          "notification-timeout@chlumskyvaclav.gmail.com"
          "notification-position@drugo.dev"
          "pkgs.gnomeExtensions.espresso"
        ];
        favorite-apps = ["firefox.desktop"];
        had-bluetooth-devices-setup = true;
        remember-mount-password = false;
        welcome-dialog-last-shown-version = "42.4";
      };
      "org/gnome/desktop/wm/keybindings" = {
        activate-window-menu = "disabled";
        #toggle-message-tray = "disabled";
        toggle-message-tray = ["<Super>v"];
        close = ["<Super>q"];
        maximize = ["disabled"];
        minimize = ["<Super>comma"];
        move-to-monitor-down = ["disabled"];
        move-to-monitor-left = ["disabled"];
        move-to-monitor-right = ["disabled"];
        move-to-monitor-up = ["disabled"];
        move-to-workspace-down = ["disabled"];
        move-to-workspace-up = ["disabled"];
        toggle-maximized = ["<Super>m"];
        unmaximize = ["disabled"];

        # On my keyboard, holding Q results in <Shift><Control><Alt>
        switch-to-workspace-left = ["<Shift><Control><Alt>Left"];
        switch-to-workspace-right = ["<Shift><Control><Alt>Right"];


        move-to-workspace-left = ["<Super><Shift><Control><Alt>Left"];
        move-to-workspace-right = ["<Super><Shift><Control><Alt>Right"];
        toggle-maximize = ["<Shift><Control><Alt>M"];
      };
  };
}
