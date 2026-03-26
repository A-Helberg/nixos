{ config, pkgs, ... }:

{
  networking.firewall.allowedTCPPorts = [ 4859 4860 ];
  networking.firewall.allowedUDPPorts = [ 5353 ]; # mDNS for local discovery

  virtualisation.oci-containers.backend = "docker";

  virtualisation.oci-containers.containers.homey-shs = {
    image = "ghcr.io/athombv/homey-shs";
    extraOptions = [
      "--network=host"
      "--privileged"
    ];
    volumes = [
      "/data/homey-shs:/homey/user/"
    ];
  };
}
