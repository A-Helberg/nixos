{ config, pkgs, ... }:
let
  s3Domain = "s3.coded.page";
  mavenDomain = "maven.coded.page";
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
      address = [
        "/${s3Domain}/${bridgeIp}"
        "/${mavenDomain}/${bridgeIp}"
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

    # Setup proxy caching for Maven
    appendHttpConfig = ''
      proxy_cache_path /data/nginx/maven levels=1:2 keys_zone=maven_cache:10m max_size=50g inactive=30d use_temp_path=off;
      
      # Force IPv4 resolution for upstreams to avoid IPv6 routing issues
      resolver 1.1.1.1 ipv6=off;
    '';

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

    virtualHosts."${mavenDomain}" = {
      # Listen specifically on the bridge interface on port 443 with SSL
      listen = [
        { addr = bridgeIp; port = 443; ssl = true; }
        { addr = bridgeIp; port = 80; }
      ];
      
      forceSSL = true;
      useACMEHost = mavenDomain;

      # Proxy for Clojars (Clojure specific)
      locations."/repo/" = {
        extraConfig = ''
          set $clojars_upstream "https://repo.clojars.org";
          
          rewrite ^/repo/(.*)$ /$1 break;
          proxy_pass $clojars_upstream;
          
          proxy_cache maven_cache;
          proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
          proxy_cache_valid 200 30d;
          proxy_cache_lock on;
          proxy_set_header Host repo.clojars.org;
          
          proxy_ssl_server_name on;
          proxy_ssl_name repo.clojars.org;
        '';
      };

      # Proxy for Maven Central
      locations."/" = {
        extraConfig = ''
          set $maven_upstream "https://repo1.maven.org";
          
          # We use a rewrite to capture the URI so we don't have to use $request_uri in proxy_pass
          rewrite ^/(.*)$ /maven2/$1 break;
          proxy_pass $maven_upstream;
          
          proxy_cache maven_cache;
          proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
          proxy_cache_valid 200 30d;
          proxy_cache_lock on;
          proxy_set_header Host repo1.maven.org;
          
          # Don't pass through client SSL headers that might confuse upstream
          proxy_ssl_server_name on;
          proxy_ssl_name repo1.maven.org;
        '';
      };
    };
  };

  # Ensure Nginx cache directory exists on the data volume
  systemd.tmpfiles.rules = [
    "d /data/nginx/maven 0750 nginx nginx -"
  ];

  # Allow Nginx to write to the data volume cache directory
  systemd.services.nginx.serviceConfig.ReadWritePaths = [ "/data/nginx/maven" ];

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

    certs."${mavenDomain}" = {
      dnsProvider = "cloudflare";
      environmentFile = "/var/lib/hydra-secrets/cloudflare-acme.env";
      reloadServices = [ "nginx.service" ];
      group = "nginx";
    };
  };
}