{ config, pkgs, lib, ... }:
let
  domain = "plane.coded.page";
  release = "v1.4.0"; # bump deliberately: api image and DB schema move together via the migrator

  # Secrets shared by the containers below. Create once on hydra:
  #   sudo sh -c 'umask 077; MINIO_PASS=$(openssl rand -hex 24); cat > /var/lib/hydra-secrets/plane.env <<EOF
  #   SECRET_KEY=$(openssl rand -hex 32)
  #   LIVE_SERVER_SECRET_KEY=$(openssl rand -hex 32)
  #   AWS_ACCESS_KEY_ID=plane-minio
  #   AWS_SECRET_ACCESS_KEY=$MINIO_PASS
  #   MINIO_ROOT_USER=plane-minio
  #   MINIO_ROOT_PASSWORD=$MINIO_PASS
  #   EOF'
  # MINIO_ROOT_* must mirror the AWS_* values — the backend talks to MinIO
  # with the AWS creds, MinIO boots with the MINIO_ROOT_* ones.
  secretsFile = "/var/lib/hydra-secrets/plane.env";

  # Containers talk to each other over a dedicated docker network. The
  # bundled Caddy proxy hardcodes upstream names (web, api, space, admin,
  # live, plane-minio), so containers whose name differs from what their
  # peers expect carry a matching --network-alias.
  redisEnv = {
    REDIS_HOST = "plane-redis";
    REDIS_PORT = "6379";
    REDIS_URL = "redis://plane-redis:6379/";
  };

  # Postgres/RabbitMQ credentials are the upstream defaults. They are only
  # reachable on the internal `plane` docker network (no published ports),
  # so they are not secret.
  backendEnv = {
    WEB_URL = "https://${domain}";
    DEBUG = "0";
    CORS_ALLOWED_ORIGINS = "https://${domain}";
    GUNICORN_WORKERS = "1";
    USE_MINIO = "1";
    # Presigned upload/download URLs point at https://<public host>/uploads;
    # MINIO_ENDPOINT_SSL forces the https scheme behind TLS termination.
    MINIO_ENDPOINT_SSL = "1";
    DATABASE_URL = "postgresql://plane:plane@plane-db/plane";
    AMQP_URL = "amqp://plane:plane@plane-mq:5672/plane";
    API_KEY_RATE_LIMIT = "60/minute";
    PGHOST = "plane-db";
    PGDATABASE = "plane";
    POSTGRES_USER = "plane";
    POSTGRES_PASSWORD = "plane";
    POSTGRES_DB = "plane";
    POSTGRES_PORT = "5432";
    AWS_REGION = "";
    AWS_S3_ENDPOINT_URL = "http://plane-minio:9000";
    AWS_S3_BUCKET_NAME = "uploads";
    FILE_SIZE_LIMIT = "5242880";
    APP_DOMAIN = domain;
  } // redisEnv;

  backend = name: entrypoint: deps: {
    image = "makeplane/plane-backend:${release}";
    cmd = [ "./bin/docker-entrypoint-${entrypoint}.sh" ];
    environment = backendEnv;
    environmentFiles = [ secretsFile ];
    volumes = [ "/data/plane/logs/${name}:/code/plane/logs" ];
    networks = [ "plane" ];
    dependsOn = deps;
  };
in
{
  # ---------------------------------------------------------
  # Plane (Community Edition): project management
  # UI: https://plane.coded.page/  (instance admin: /god-mode/)
  # Runs the upstream self-host stack as oci-containers; all
  # state lives under /data/plane. Host nginx terminates TLS
  # and hands everything to the bundled Caddy proxy container,
  # which owns the path routing (/, /api, /spaces, /god-mode,
  # /live, /uploads, ...) and tracks upstream layout changes.
  # ---------------------------------------------------------
  virtualisation.oci-containers.containers = {
    plane-web = {
      image = "makeplane/plane-frontend:${release}";
      networks = [ "plane" ];
      extraOptions = [ "--network-alias=web" ];
    };

    plane-space = {
      image = "makeplane/plane-space:${release}";
      networks = [ "plane" ];
      extraOptions = [ "--network-alias=space" ];
    };

    plane-admin = {
      image = "makeplane/plane-admin:${release}";
      networks = [ "plane" ];
      extraOptions = [ "--network-alias=admin" ];
    };

    plane-live = {
      image = "makeplane/plane-live:${release}";
      environment = { API_BASE_URL = "http://api:8000"; } // redisEnv;
      environmentFiles = [ secretsFile ]; # LIVE_SERVER_SECRET_KEY (must match api)
      networks = [ "plane" ];
      extraOptions = [ "--network-alias=live" ];
    };

    # plane-minio must be up when the api entrypoint runs its bucket check —
    # a missing bucket is never retried and presigned uploads then 404.
    plane-api = (backend "api" "api" [ "plane-db" "plane-redis" "plane-mq" "plane-minio" ]) // {
      extraOptions = [ "--network-alias=api" ];
    };
    plane-worker = backend "worker" "worker" [ "plane-db" "plane-redis" "plane-mq" ];
    plane-beat-worker = backend "beat-worker" "beat" [ "plane-db" "plane-redis" "plane-mq" ];
    # One-shot: runs wait_for_db + migrate, then exits. The api/worker
    # entrypoints block on wait_for_migrations, so no strict ordering is
    # needed. Restart=on-failure (the oci-containers default) matches the
    # upstream compose restart policy and stops it from looping on success.
    plane-migrator = backend "migrator" "migrator" [ "plane-db" "plane-redis" ];

    plane-db = {
      image = "postgres:15.7-alpine";
      cmd = [ "postgres" "-c" "max_connections=1000" ];
      environment = {
        POSTGRES_USER = "plane";
        POSTGRES_PASSWORD = "plane";
        POSTGRES_DB = "plane";
        PGDATA = "/var/lib/postgresql/data";
      };
      volumes = [ "/data/plane/pgdata:/var/lib/postgresql/data" ];
      networks = [ "plane" ];
    };

    plane-redis = {
      image = "valkey/valkey:7.2.11-alpine";
      volumes = [ "/data/plane/redis:/data" ];
      networks = [ "plane" ];
    };

    plane-mq = {
      image = "rabbitmq:3.13.6-management-alpine";
      environment = {
        RABBITMQ_DEFAULT_USER = "plane";
        RABBITMQ_DEFAULT_PASS = "plane";
        RABBITMQ_DEFAULT_VHOST = "plane";
      };
      volumes = [ "/data/plane/rabbitmq:/var/lib/rabbitmq" ];
      networks = [ "plane" ];
    };

    plane-minio = {
      image = "minio/minio:latest";
      cmd = [ "server" "/export" "--console-address" ":9090" ];
      environmentFiles = [ secretsFile ]; # MINIO_ROOT_USER / MINIO_ROOT_PASSWORD
      volumes = [ "/data/plane/minio:/export" ];
      networks = [ "plane" ];
    };

    plane-proxy = {
      image = "makeplane/plane-proxy:${release}";
      environment = {
        APP_DOMAIN = domain;
        SITE_ADDRESS = ":80"; # plain HTTP inside; host nginx terminates TLS
        FILE_SIZE_LIMIT = "5242880";
        BUCKET_NAME = "uploads";
      };
      ports = [ "127.0.0.1:3100:80" ];
      volumes = [
        "/data/plane/proxy/config:/config"
        "/data/plane/proxy/data:/data"
      ];
      networks = [ "plane" ];
      extraOptions = [ "--network-alias=proxy" ];
    };
  };

  # Container entrypoints (postgres, rabbitmq, minio) chown their own data
  # dirs on first boot.
  systemd.tmpfiles.rules = [
    "d /data/plane 0750 root root -"
    "d /data/plane/pgdata 0750 root root -"
    "d /data/plane/redis 0750 root root -"
    "d /data/plane/rabbitmq 0750 root root -"
    "d /data/plane/minio 0750 root root -"
    "d /data/plane/proxy 0750 root root -"
    "d /data/plane/proxy/config 0750 root root -"
    "d /data/plane/proxy/data 0750 root root -"
    "d /data/plane/logs 0750 root root -"
    "d /data/plane/logs/api 0750 root root -"
    "d /data/plane/logs/worker 0750 root root -"
    "d /data/plane/logs/beat-worker 0750 root root -"
    "d /data/plane/logs/migrator 0750 root root -"
  ];

  systemd.services = {
    docker-network-plane = {
      description = "Docker network for the Plane stack";
      after = [ "docker.service" ];
      requires = [ "docker.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${pkgs.docker}/bin/docker network inspect plane >/dev/null 2>&1 || \
          ${pkgs.docker}/bin/docker network create plane
      '';
    };
  }
  // lib.genAttrs
    (map (n: "docker-${n}") [
      "plane-web"
      "plane-space"
      "plane-admin"
      "plane-live"
      "plane-api"
      "plane-worker"
      "plane-beat-worker"
      "plane-migrator"
      "plane-db"
      "plane-redis"
      "plane-mq"
      "plane-minio"
      "plane-proxy"
    ])
    (_: {
      after = [ "docker-network-plane.service" ];
      requires = [ "docker-network-plane.service" ];
      # Hold the stack until the secrets file exists (see comment at top).
      unitConfig.ConditionPathExists = secretsFile;
    });

  services.nginx.virtualHosts."${domain}" = {
    forceSSL = true;
    useACMEHost = domain;

    locations."/" = {
      proxyPass = "http://127.0.0.1:3100";
      # /live/ is a WebSocket endpoint (collaborative editing).
      proxyWebsockets = true;
      # No Host header here: recommendedProxySettings already sets it, and
      # a duplicate makes Go's net/http (Caddy) reject the request with 400.
      extraConfig = ''
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
      '';
    };
  };

  security.acme.certs."${domain}" = {
    dnsProvider = "cloudflare";
    environmentFile = "/var/lib/hydra-secrets/cloudflare-acme.env";
    reloadServices = [ "nginx.service" ];
    group = "nginx";
  };
}
