{ config, pkgs, ... }:
{
  # ---------------------------------------------------------
  # Mailpit: catch-all SMTP sink + web UI, so selfhosted services
  # (forgejo, ...) have somewhere to deliver mail without a real
  # mail account. Nothing is forwarded anywhere.
  # Point services at smtp://10.253.10.2:1025 (no auth, no TLS).
  # Browse caught mail at http://10.253.10.2:8025/
  # ---------------------------------------------------------
  services.mailpit.instances.default = {
    listen = "0.0.0.0:8025"; # web UI + API
    smtp = "0.0.0.0:1025"; # bound on all interfaces so docker services reach it via the host IP
    max = 5000; # messages kept before the oldest are pruned
  };

  networking.firewall.allowedTCPPorts = [ 1025 8025 ];
}
