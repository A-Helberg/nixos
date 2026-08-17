{ config, pkgs, ... }:
let
  webDomain = "plan.coded.page";
  apiDomain = "api.plan.coded.page";
  dataDir = "/data/itsaplan";
  envFile = "/var/lib/hydra-secrets/itsaplan.env";
  secretsDir = "/var/lib/hydra-secrets/itsaplan";

  # To update: bump the tag, clear the hash, rebuild, and paste the hash
  # from the mismatch error (or `nix flake prefetch github:croffasia/itsaplan/<tag>`).
  src = pkgs.fetchFromGitHub {
    owner = "croffasia";
    repo = "itsaplan";
    rev = "v0.8.0";
    hash = "sha256-1KzewNKyfvWeDqj8W+M9g+XB10JEFxaE5D5iqpmf/oU=";
  };

  # On top of the upstream compose file: keep the published ports off the
  # LAN (docker bypasses the NixOS firewall) and put state under /data
  # instead of named volumes. 8092/8093 are free on hydra; 3000/3001 are
  # taken by Flood/Forgejo anyway.
  composeOverride = pkgs.writeText "itsaplan-compose.override.yml" ''
    services:
      postgres:
        volumes:
          - ${dataDir}/postgres:/var/lib/postgresql/data
      minio:
        volumes:
          - ${dataDir}/minio:/data
      api:
        ports: !override
          - "127.0.0.1:8093:3000"
        # Pi-hole, so mirrored .local names resolve (avahi.nix); docker's
        # embedded DNS still handles container names first, and everything
        # else forwards through pi-hole's normal upstreams.
        dns:
          - 10.253.10.2
      worker:
        dns:
          - 10.253.10.2
      web:
        ports: !override
          - "127.0.0.1:8092:3001"
  '';

  composeCmd = "${pkgs.docker-compose}/bin/docker-compose"
    + " --project-directory ${src}"
    + " -f ${src}/docker-compose.yml -f ${composeOverride}"
    + " --env-file ${envFile}";
in
{
  # ---------------------------------------------------------
  # It's a Plan: issue tracker for people and AI agents
  # (https://itsaplan.dev, no NixOS module). Runs the official
  # compose stack — postgres, minio, api, worker, telegram bot,
  # web — built from a pinned source checkout; upstream ships
  # no prebuilt images.
  #
  # Web UI: https://plan.coded.page/  API: https://api.plan.coded.page/
  # (LAN; needs Cloudflare DNS records for BOTH names -> 10.253.10.2.)
  # The first account registered becomes the instance admin.
  # Outbound mail is configured in-app (admin > mail transport):
  # point SMTP at Mailpit, 10.253.10.2:1025, no auth/TLS.
  #
  # Secrets are auto-generated on first boot by
  # itsaplan-setup.service into /var/lib/hydra-secrets/itsaplan/.
  # Logs: journalctl -u itsaplan, or docker logs itsaplan-<service>-1.
  # ---------------------------------------------------------
  virtualisation.docker.enable = true;

  # Only the parent dir. tmpfiles re-applies ownership on every activation,
  # and a rule for the postgres subdir once chowned it back to root mid-run,
  # locking uid-70 postgres out of its own data. Docker creates the bind-mount
  # subdirs itself and the images manage their own ownership.
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 root root -"
  ];

  systemd.services.itsaplan-setup = {
    description = "It's a Plan secrets and env file setup";
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.openssl ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    # Secrets are generated once and kept (hex: the postgres one is embedded
    # in DATABASE_URL, and APP_ENCRYPTION_KEY must never change — rotating it
    # makes stored AI-provider credentials undecryptable). The env file is
    # reassembled from them on every boot.
    script = ''
      umask 077
      mkdir -p ${secretsDir}
      for s in postgres auth encryption worker s3; do
        [ -s ${secretsDir}/$s ] || openssl rand -hex 32 > ${secretsDir}/$s
      done

      printf '%s\n' \
        "API_URL=https://${apiDomain}" \
        "APP_URL=https://${webDomain}" \
        "COOKIE_DOMAIN=${webDomain}" \
        "POSTGRES_USER=itsaplan" \
        "POSTGRES_DB=itsaplan" \
        "POSTGRES_PASSWORD=$(cat ${secretsDir}/postgres)" \
        "BETTER_AUTH_SECRET=$(cat ${secretsDir}/auth)" \
        "APP_ENCRYPTION_KEY=$(cat ${secretsDir}/encryption)" \
        "WORKER_INTERNAL_TOKEN=$(cat ${secretsDir}/worker)" \
        "S3_ACCESS_KEY_ID=itsaplan" \
        "S3_SECRET_ACCESS_KEY=$(cat ${secretsDir}/s3)" \
        "S3_BUCKET=planner-attachments" \
        "S3_REGION=us-east-1" \
        "EMAIL_FROM=Its a Plan <itsaplan@coded.page>" \
        "TELEMETRY_DISABLED=1" \
        > ${envFile}
    '';
  };

  systemd.services.itsaplan = {
    description = "It's a Plan docker compose stack";
    wantedBy = [ "multi-user.target" ];
    after = [ "docker.service" "docker.socket" "itsaplan-setup.service" ];
    requires = [ "docker.service" "itsaplan-setup.service" ];
    serviceConfig = {
      # --build: images are built from the pinned checkout; after the first
      # build this is a cached no-op. `up` stays attached so logs aggregate
      # in the journal.
      ExecStart = "${composeCmd} up --build --remove-orphans";
      ExecStop = "${composeCmd} down";
      Restart = "always";
      RestartSec = 10;
    };
  };

  services.nginx.virtualHosts = {
    "${webDomain}" = {
      forceSSL = true;
      useACMEHost = webDomain;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8092";
        proxyWebsockets = true;
        # Streamed chat responses pass through here too: no buffering, and
        # generous timeouts for long-running agent responses.
        extraConfig = ''
          proxy_read_timeout 900s;
          proxy_send_timeout 900s;
          proxy_buffering off;
        '';
      };
    };

    "${apiDomain}" = {
      forceSSL = true;
      useACMEHost = webDomain;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8093";
        proxyWebsockets = true;
        # Agent runs and live updates stream through the api; don't buffer
        # them, and allow long-lived connections.
        extraConfig = ''
          proxy_read_timeout 900s;
          proxy_send_timeout 900s;
          proxy_buffering off;
        '';
      };
    };
  };

  security.acme.certs."${webDomain}" = {
    dnsProvider = "cloudflare";
    environmentFile = "/var/lib/hydra-secrets/cloudflare-acme.env";
    reloadServices = [ "nginx.service" ];
    group = "nginx";
    extraDomainNames = [ apiDomain ];
  };
}
