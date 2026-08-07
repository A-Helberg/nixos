{ config, pkgs, ... }:
{
  # ---------------------------------------------------------
  # Tailscale: reach hydra (and the whole LAN) from anywhere.
  # Advertises 10.253.0.0/16 as a subnet route, so tailnet
  # devices can reach any LAN host by its normal IP without
  # that host running tailscale. Existing DNS records pointing
  # at 10.253.10.2 keep working remotely.
  #
  # One-time setup on hydra after deploy:
  #   sudo tailscale up
  # then approve the advertised route for hydra at
  # https://login.tailscale.com/admin/machines
  # ---------------------------------------------------------
  services.tailscale = {
    enable = true;
    # Enables IP forwarding so the advertised route passes traffic.
    useRoutingFeatures = "server";
    # Applied via `tailscale set` on every service start, so the
    # route advertisement survives reboots and re-authentication.
    extraSetFlags = [ "--advertise-routes=10.253.0.0/16" ];
  };
}
