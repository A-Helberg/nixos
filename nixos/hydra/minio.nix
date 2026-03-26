{ ... }:
{
  services.minio = {
    enable = true;

    # Keep object storage on the dedicated data volume.
    dataDir = [ "/data/minio" ];

    # S3 API endpoint for runners/tools.
    listenAddress = "127.0.0.1:9000";
    # Keep the admin console local-only for now.
    consoleAddress = "0.0.0.0:9001";

    # File must define MINIO_ROOT_USER and MINIO_ROOT_PASSWORD.
    rootCredentialsFile = "/var/lib/hydra-secrets/minio-root";
  };

  # Expose Admin Console port to local network.
  networking.firewall.allowedTCPPorts = [ 9001 ];
}
