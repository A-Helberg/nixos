{ config, pkgs, lib, ... }:
{
  # The whole LAN's DNS: never leave FTL dead. systemd counts death by
  # SIGHUP/SIGTERM as a *clean* exit (this once left DNS down for the
  # network when a stray HUP killed FTL mid-startup), so on-failure is
  # not enough — restart unconditionally.
  # (The module already sets RestartSec=1.)
  systemd.services.pihole-ftl.serviceConfig.Restart = lib.mkForce "always";

  # ---------------------------------------------------------
  # Pi-hole: network-wide ad blocking DNS
  # Point router DHCP (or individual devices) at 10.253.10.2.
  # Admin UI: http://10.253.10.2:8090/
  # Set the UI password once on hydra: sudo pihole setpassword
  # ---------------------------------------------------------
  services.pihole-ftl = {
    enable = true;
    openFirewallDNS = true; # 53 TCP/UDP
    openFirewallWebserver = true; # 8090, from settings.webserver.port via pihole-web

    queryLogDeleter.enable = true; # drop query logs older than 90 days

    lists = [
      {
        url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
        description = "StevenBlack unified hosts";
      }
      # StevenBlack alone misses in-app ad SDK infrastructure: TikTok/Pangle
      # ads got through via p16-ad-sg.ibyteimg.com, i18n-pglstatp.com and
      # ib.snssdk.com, all of which Pro++ blocks (ABP format, zone-wide).
      {
        url = "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.plus.txt";
        description = "hagezi Multi PRO++";
      }
    ];

    settings = {
      dns = {
        upstreams = [ "1.1.1.1" "8.8.8.8" ];
        # Default listeningMode LOCAL answers only directly attached
        # subnets (10.253.0.0/16 on eno1) — what we want.
      };
      # Required so declaratively configured lists load via the pihole CLI.
      webserver.api.cli_pw = true;
    };
  };

  services.pihole-web = {
    enable = true;
    ports = [ 8090 ]; # 80/443 nginx, 8080 fireactions, 8082 nexus
  };
}
