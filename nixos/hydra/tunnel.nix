{ config, pkgs, ... }:
{
  services.cloudflared = {
    enable = true;
    tunnels = {
      "hydra-tunnel" = {
        credentialsFile = "/var/lib/hydra-secrets/cloudflare-tunnel.json";
        default = "http_status:404";
        ingress = {
          # Route external traffic directly to the local MinIO S3 API
          "s3.coded.page" = "http://127.0.0.1:9000";
        };
      };
    };
  };
}