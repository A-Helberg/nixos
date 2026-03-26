{ config, pkgs, ... }:
{
  # Create a configuration directory for apt-cacher-ng
  environment.etc."apt-cacher-ng/acng.conf".text = ''
    CacheDir: /data/apt-cacher-ng
    LogDir: /var/log/apt-cacher-ng
    Port: 3142
    BindAddress: 0.0.0.0
    ExThreshold: 30
    # PassThroughPattern allows HTTPS connections to pass through without caching
    # This is required so we don't break non-apt HTTPS traffic if the proxy is set globally
    PassThroughPattern: .*
  '';

  systemd.services.apt-cacher-ng = {
    description = "Apt-Cacher NG";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      ExecStartPre = [
        "${pkgs.coreutils}/bin/mkdir -p /data/apt-cacher-ng"
        "${pkgs.coreutils}/bin/mkdir -p /var/log/apt-cacher-ng"
      ];
      ExecStart = "${pkgs.apt-cacher-ng}/bin/apt-cacher-ng -c /etc/apt-cacher-ng ForeGround=1";
      User = "root";
      Restart = "always";
    };
  };

  # Open the port for the VMs on the bridge
  networking.firewall.allowedTCPPorts = [ 3142 ];
}