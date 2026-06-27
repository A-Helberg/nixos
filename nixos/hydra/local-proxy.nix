{ config, pkgs, ... }:
let
  s3Domain = "s3.coded.page";
  cacheDomain = "cache.coded.page";
in
{
  # ---------------------------------------------------------
  # 1. Nginx: LAN Proxy with Valid SSL
  # ---------------------------------------------------------
  services.nginx = {
    enable = true;

    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    clientMaxBodySize = "50G";

    virtualHosts."${s3Domain}" = {
      forceSSL = true;
      useACMEHost = s3Domain;

      locations."/" = {
        proxyPass = "http://127.0.0.1:9000";
        extraConfig = ''
          proxy_set_header Host $host;
        '';
      };
    };

    # TLS frontend for Nexus — caching is handled by Nexus itself.
    virtualHosts."${cacheDomain}" = {
      forceSSL = true;
      useACMEHost = cacheDomain;

      locations."/" = {
        proxyPass = "http://127.0.0.1:8082";
        extraConfig = ''
          # Nexus needs the real host header for repository URL generation.
          proxy_set_header Host $host;
          # Large artifacts (JARs, tarballs) can take a while to proxy on first fetch.
          proxy_read_timeout 300s;
          proxy_send_timeout 300s;
        '';
      };
    };
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];

  # ---------------------------------------------------------
  # 2. ACME: Fetch Let's Encrypt Cert via Cloudflare DNS
  # ---------------------------------------------------------
  security.acme = {
    acceptTerms = true;
    defaults.email = "helberg.andre@gmail.com";

    certs."${s3Domain}" = {
      dnsProvider = "cloudflare";
      # This file must contain: CF_DNS_API_TOKEN=your_token_here
      environmentFile = "/var/lib/hydra-secrets/cloudflare-acme.env";
      reloadServices = [ "nginx.service" ];
      group = "nginx";
    };

    certs."${cacheDomain}" = {
      dnsProvider = "cloudflare";
      environmentFile = "/var/lib/hydra-secrets/cloudflare-acme.env";
      reloadServices = [ "nginx.service" ];
      group = "nginx";
    };
  };
}