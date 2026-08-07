{ config, pkgs, ... }:
let
  domain = "git.coded.page";
in
{
  # ---------------------------------------------------------
  # Forgejo: self-hosted git forge
  # UI: https://git.coded.page/ (LAN)
  # Git over SSH: ssh://git@git.coded.page:2222/owner/repo.git
  #
  # Registration is disabled. Create the first admin user on hydra:
  #   sudo -u forgejo env FORGEJO_WORK_DIR=/data/forgejo FORGEJO_CUSTOM=/data/forgejo/custom \
  #     forgejo admin user create --username andre --email helberg.andre@gmail.com \
  #     --password '...' --admin --must-change-password
  # ---------------------------------------------------------
  services.forgejo = {
    enable = true;
    stateDir = "/data/forgejo";
    lfs.enable = true;

    # SQLite is plenty for a personal instance and keeps state
    # self-contained under /data/forgejo.
    database.type = "sqlite3";

    settings = {
      server = {
        DOMAIN = domain;
        ROOT_URL = "https://${domain}/";
        HTTP_ADDR = "127.0.0.1";
        # 3000 is taken by Flood (private module).
        HTTP_PORT = 3001;
        # Built-in SSH server; host sshd keeps port 22.
        START_SSH_SERVER = true;
        SSH_PORT = 2222;
        SSH_LISTEN_PORT = 2222;
      };
      service.DISABLE_REGISTRATION = true;
    };
  };

  # CLI for admin tasks (user creation, etc.).
  environment.systemPackages = [ config.services.forgejo.package ];

  networking.firewall.allowedTCPPorts = [ 2222 ];

  services.nginx.virtualHosts."${domain}" = {
    forceSSL = true;
    useACMEHost = domain;

    # NB: recommendedProxySettings already injects proxy_set_header Host
    # $host into every proxied location; adding it again in extraConfig
    # sends a duplicate Host header, which Go's net/http rejects with 400.
    locations."/".proxyPass = "http://127.0.0.1:3001";
  };

  security.acme.certs."${domain}" = {
    dnsProvider = "cloudflare";
    environmentFile = "/var/lib/hydra-secrets/cloudflare-acme.env";
    reloadServices = [ "nginx.service" ];
    group = "nginx";
  };
}
