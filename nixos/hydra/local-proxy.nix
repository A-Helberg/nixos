{ config, pkgs, ... }:
let
  s3Domain = "s3.coded.page";
  cacheDomain = "cache.coded.page";
  bridgeIp = "10.200.0.1";
in
{
  # ---------------------------------------------------------
  # 1. DNSMasq: Local DNS Server for the VMs
  # ---------------------------------------------------------
  services.dnsmasq = {
    enable = true;
    settings = {
      # Only listen on the bridge interface so we don't interfere with the host's DNS
      interface = "fireactions0";
      bind-interfaces = true;

      # Resolve our local domains to the bridge IP (Nginx listens there)
      address = [
        "/${s3Domain}/${bridgeIp}"
        "/${cacheDomain}/${bridgeIp}"
      ];

      # Forward all other requests to a public DNS resolver
      server = [ "1.1.1.1" "1.0.0.1" ];
    };
  };

  # Open DNS port for the VMs
  networking.firewall.allowedUDPPorts = [ 53 ];
  networking.firewall.allowedTCPPorts = [ 53 ];

  # ---------------------------------------------------------
  # 2. Nginx: Local Proxy with Valid SSL
  # ---------------------------------------------------------
  services.nginx = {
    enable = true;

    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    clientMaxBodySize = "50G";

    virtualHosts."${s3Domain}" = {
      listen = [
        { addr = bridgeIp; port = 443; ssl = true; }
        { addr = bridgeIp; port = 80; }
      ];

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
      listen = [
        { addr = bridgeIp; port = 443; ssl = true; }
        { addr = bridgeIp; port = 80; }
      ];

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

  # Open HTTP/HTTPS ports for the VMs on the bridge
  networking.firewall.interfaces.fireactions0.allowedTCPPorts = [ 80 443 ];

  # ---------------------------------------------------------
  # 3. ACME: Fetch Let's Encrypt Cert via Cloudflare DNS
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