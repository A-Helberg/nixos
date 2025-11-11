{ config, pkgs, inputs, ... }:
{
  imports = [
    ../../darwin
  ];

  networking.hostName = "Zanes-MacBook-Air-2";
  system.primaryUser = "andre";

  system.defaults.dock.persistent-apps = [
    "/Applications/Ghostty.app"
  ];
}
