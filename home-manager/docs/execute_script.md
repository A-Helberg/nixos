# Execute a script

``` nix
{ config, pkgs, ... }:
let
  myScript = pkgs.writeShellScriptBin "myScript" ''
    #!/usr/bin/env bash
    echo "Running my custom script"
  '';
in
{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "andre";
  ...

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = [
    myScript
  ]
}
```
