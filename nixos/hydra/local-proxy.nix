{ config, pkgs, ... }:
let
  cacheDomain = "cache.coded.page";
in
{
  # ---------------------------------------------------------
  # 1. Caddy: LAN reverse proxy with valid SSL
  # Front door for every HTTPS site on hydra. Certs come from
  # security.acme (Cloudflare DNS-01) via useACMEHost, so stock caddy
  # works without the caddy-dns plugin; the caddy module sets each
  # cert's group and reload hook. nginx survives only as the rtorrent
  # SCGI bridge (private mullvad-rtorrent.nix), which caddy can't do.
  # ---------------------------------------------------------
  services.caddy = {
    enable = true;

    # TLS frontend for Nexus — caching is handled by Nexus itself.
    # Caddy passes the original Host through (Nexus needs it for
    # repository URLs), has no body size limit and no response timeout
    # by default, so large first-fetch artifacts need nothing extra.
    virtualHosts."${cacheDomain}" = {
      useACMEHost = cacheDomain;
      extraConfig = "reverse_proxy 127.0.0.1:8082";
    };
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];

  # ---------------------------------------------------------
  # 2. ACME: Fetch Let's Encrypt Cert via Cloudflare DNS
  # ---------------------------------------------------------
  security.acme = {
    acceptTerms = true;
    defaults.email = "helberg.andre@gmail.com";

    certs."${cacheDomain}" = {
      dnsProvider = "cloudflare";
      # This file must contain: CF_DNS_API_TOKEN=your_token_here
      environmentFile = "/var/lib/hydra-secrets/cloudflare-acme.env";
    };
  };
}