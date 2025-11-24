{ config, pkgs, ... }:
{
  imports = [
    ./common/base.nix
  ];

  home.homeDirectory = "/home/andre";

  home.packages = with pkgs; [
    gns3-gui
    (vagrant.override { withLibvirt = false; })
    virt-manager
    wireshark
    cider
    libreoffice
    
    gnomeExtensions.notification-timeout
    gnomeExtensions.system-monitor
    gnomeExtensions.gsconnect
    gnomeExtensions.espresso
    gnomeExtensions.notification-banner-position
  ];

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
        "notification-timeout@chlumskyvaclav.gmail.com"
        "notification-position@drugo.dev"
      ];
      favorite-apps = ["firefox.desktop"];
      had-bluetooth-devices-setup = true;
      remember-mount-password = false;
      welcome-dialog-last-shown-version = "42.4";
    };
    
    "org/gnome/desktop/wm/keybindings" = {
      activate-window-menu = "disabled";
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
      switch-to-workspace-left = ["<Shift><Control><Alt>Left"];
      switch-to-workspace-right = ["<Shift><Control><Alt>Right"];
      move-to-workspace-left = ["<Super><Shift><Control><Alt>Left"];
      move-to-workspace-right = ["<Super><Shift><Control><Alt>Right"];
      toggle-maximize = ["<Shift><Control><Alt>M"];
    };
  };
}
