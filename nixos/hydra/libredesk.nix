{ config, pkgs, lib, ... }:
let
  domain = "desk.coded.page";
  port = 9000;
  dataDir = "/data/libredesk";
  version = "2.8.0";

  # Upstream's static release binary (web UI embedded). To update: bump
  # the version, clear the hash, rebuild, paste the hash from the error.
  libredesk = pkgs.stdenvNoCC.mkDerivation {
    pname = "libredesk";
    inherit version;
    src = pkgs.fetchurl {
      url = "https://github.com/abhinavxd/libredesk/releases/download/v${version}/libredesk_${version}_linux_amd64.tar.gz";
      hash = "sha256-hjBE5FJ7mEObN7wVnQGgybxZePCQSM8oLxyT/xAj2+0=";
    };
    sourceRoot = ".";
    installPhase = "install -Dm755 libredesk $out/bin/libredesk";
  };

  # Upstream's config.sample.toml, with the values that differ here.
  # The encryption key is filled in at start (see preStart).
  configTemplate = (pkgs.formats.toml { }).generate "libredesk.toml" {
    app = {
      log_level = "info";
      env = "prod";
      # Updates come from the version above, not the admin banner.
      check_updates = false;
      encryption_key = "@ENCRYPTION_KEY@";
      server = {
        address = "127.0.0.1:${toString port}";
        socket = "";
        disable_secure_cookies = false;
        session_lifetime = "9h";
        read_timeout = "60s";
        write_timeout = "60s";
        max_body_size = 104857600;
        read_buffer_size = 65536;
        keepalive_timeout = "10s";
      };
    };
    upload = {
      provider = "fs";
      fs = {
        upload_path = "${dataDir}/uploads";
        expiry = "1h";
      };
    };
    # Unix socket and peer auth: no database password. The driver always
    # sends one, so it gets a placeholder that peer auth never checks.
    db = {
      host = "/run/postgresql";
      port = 5432;
      user = "libredesk";
      password = "unused-peer-auth";
      database = "libredesk";
      ssl_mode = "disable";
      max_open = 30;
      max_idle = 30;
      max_lifetime = "300s";
    };
    redis = {
      address = "127.0.0.1:${toString config.services.redis.servers.libredesk.port}";
      user = "";
      password = "";
      db = 0;
    };
    message = {
      outgoing_queue_workers = 10;
      incoming_queue_workers = 10;
      message_outgoing_scan_interval = "50ms";
      incoming_queue_size = 5000;
      outgoing_queue_size = 5000;
    };
    notification = {
      concurrency = 2;
      queue_size = 2000;
    };
    automation.worker_count = 10;
    ai_agent = {
      worker_count = 10;
      queue_size = 1000;
      max_steps = 6;
      max_history_messages = 30;
    };
    autoassigner.autoassign_interval = "5m";
    webhook = {
      workers = 5;
      queue_size = 10000;
      timeout = "15s";
    };
    ssrf = {
      enabled = false;
      allowed_cidrs = [ ];
    };
    conversation = {
      unsnooze_interval = "5m";
      draft_retention_duration = "360h";
      continuity_scan_interval = "5m";
    };
    sla.evaluation_interval = "5m";
    rate_limit = {
      widget = { enabled = true; requests_per_minute = 100; };
      auth = { enabled = true; requests_per_minute = 30; };
      public = { enabled = true; requests_per_minute = 100; };
      media = { enabled = true; requests_per_minute = 300; };
    };
  };
in
{
  # ---------------------------------------------------------
  # LibreDesk: self-hosted customer support desk
  # (https://libredesk.io, not in nixpkgs). Upstream's release binary
  # as a systemd service, on NixOS's Postgres and Redis.
  #
  # Web UI: https://desk.coded.page/, public through hydra-tunnel
  # (Cloudflare terminates TLS; tunnel.nix creates the DNS record), so
  # customers can reach the chat widget and help center.
  # Log in as `System` with the password generated on first start:
  #   sudo cat /var/lib/libredesk/system-password
  # Then set Settings -> General -> Root URL to https://desk.coded.page.
  # Logs: journalctl -u libredesk
  # ---------------------------------------------------------
  services.postgresql = {
    enable = true;
    # First Postgres on hydra; upstream's compose runs 17.
    package = pkgs.postgresql_17;
    ensureDatabases = [ "libredesk" ];
    ensureUsers = [
      {
        name = "libredesk";
        ensureDBOwnership = true;
      }
    ];
  };

  services.redis.servers.libredesk = {
    enable = true;
    port = 6379;
    bind = "127.0.0.1";
  };

  users.users.libredesk = {
    isSystemUser = true;
    group = "libredesk";
  };
  users.groups.libredesk = { };

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 libredesk libredesk -"
    "d ${dataDir}/uploads 0750 libredesk libredesk -"
  ];

  systemd.services.libredesk = {
    description = "LibreDesk customer support desk";
    wantedBy = [ "multi-user.target" ];
    after = [ "postgresql.service" "redis-libredesk.service" ];
    requires = [ "postgresql.service" "redis-libredesk.service" ];
    path = [ pkgs.openssl pkgs.gnused libredesk ];
    serviceConfig = {
      User = "libredesk";
      Group = "libredesk";
      StateDirectory = "libredesk";
      StateDirectoryMode = "0700";
      RuntimeDirectory = "libredesk";
      RuntimeDirectoryMode = "0700";
      WorkingDirectory = dataDir;
      Restart = "always";
      RestartSec = 5;
    };
    # The encryption key is generated once and kept: it encrypts stored
    # credentials (mail passwords, API keys), so it must never change.
    # The system user's password only applies to the first --install;
    # after that, change it in the UI.
    preStart = ''
      umask 077
      state=$STATE_DIRECTORY
      [ -s $state/encryption-key ] || openssl rand -hex 16 > $state/encryption-key
      # Meets LibreDesk's rule: 10-72 chars, upper, lower, digit, symbol.
      [ -s $state/system-password ] || printf 'Ld1-%s\n' "$(openssl rand -hex 12)" > $state/system-password

      sed "s/@ENCRYPTION_KEY@/$(cat $state/encryption-key)/" ${configTemplate} \
        > $RUNTIME_DIRECTORY/config.toml

      LIBREDESK_SYSTEM_USER_PASSWORD=$(cat $state/system-password) \
        libredesk --install --idempotent-install --yes --config $RUNTIME_DIRECTORY/config.toml
      libredesk --upgrade --yes --config $RUNTIME_DIRECTORY/config.toml
    '';
    script = ''
      exec libredesk --config $RUNTIME_DIRECTORY/config.toml
    '';
  };

  services.cloudflared.tunnels."hydra-tunnel".ingress."${domain}" =
    "http://127.0.0.1:${toString port}";
}
