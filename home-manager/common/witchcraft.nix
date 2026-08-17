{ config, pkgs, ... }:
{
  # The Witchcraft browser extension fetches userscripts from
  # http://localhost:5743/<domain>.js; serve the stowed scripts dir for it.
  launchd.agents.witchcraft = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.python3}/bin/python3"
        "-m"
        "http.server"
        "5743"
        "--bind"
        "127.0.0.1"
        "--directory"
        "${config.home.homeDirectory}/.config/witchcraft"
      ];
      RunAtLoad = true;
      KeepAlive = true;
    };
  };
}
