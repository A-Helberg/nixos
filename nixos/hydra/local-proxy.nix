{ config, pkgs, ... }:
let
  s3Domain = "s3.coded.page";
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
      
      # Resolve our S3 domain to the local bridge IP (which Nginx is listening on)
      address = "/${s3Domain}/${bridgeIp}";
      
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
      # Listen specifically on the bridge interface
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
      # We don't need to reload a public webserver, just our local Nginx
      reloadServices = [ "nginx.service" ];
      group = "nginx";
    };
  };
}