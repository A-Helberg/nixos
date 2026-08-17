{ config, pkgs, lib, ... }:
let
  # LAN hosts mirrored from mDNS into Pi-hole (see below). Bare names;
  # ".local" is appended.
  mdnsMirrorNames = [ "phoenix" ];
  mdnsHostsDir = "/var/lib/pihole-mdns-hosts.d";
  mdnsHostsFile = "${mdnsHostsDir}/mdns.hosts";
in
{
  # ---------------------------------------------------------
  # Avahi: mDNS/Bonjour. Lets hydra resolve LAN .local names
  # (nssmdns4 hooks it into glibc's resolver, so every program
  # gets it), and publishes hydra.local for the rest of the LAN.
  # openFirewall defaults to true (5353/udp).
  #
  # NB: homebridge (host-network container) does its own HAP
  # mDNS advertising on 5353; multicast sockets are shared, so
  # they coexist — but if homebridge discovery ever breaks,
  # look here first.
  # ---------------------------------------------------------
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  # ---------------------------------------------------------
  # mDNS -> Pi-hole bridge. Docker containers can't do mDNS
  # (bridge networks get plain DNS only, and multicast doesn't
  # cross the bridge), so a timer resolves the names above via
  # avahi and mirrors them into Pi-hole as ordinary A records.
  # Containers that need .local names point their DNS at
  # 10.253.10.2 (see itsaplan.nix); the rest of the LAN gets
  # them for free.
  # ---------------------------------------------------------
  # hostsdir, NOT addn-hosts: dnsmasq watches the directory with inotify
  # and picks up changes by itself, so the mirror never has to signal FTL.
  # (An earlier version sent SIGHUP via systemctl kill; it raced an FTL
  # restart, landed before FTL's handler was installed, and took the
  # LAN's DNS down. No signals.)
  services.pihole-ftl.settings.misc.dnsmasq_lines = [
    "hostsdir=${mdnsHostsDir}"
  ];

  systemd.tmpfiles.rules = [
    "d ${mdnsHostsDir} 0755 root root -"
    "f ${mdnsHostsFile} 0644 root root -"
  ];

  systemd.services.mdns-pihole-mirror = {
    description = "Mirror mDNS names into Pi-hole";
    path = [ pkgs.avahi ];
    serviceConfig.Type = "oneshot";
    # A name that stops resolving (machine asleep) keeps its last known
    # address rather than being dropped: for DHCP laptops the old IP is
    # usually still right once they wake, and stale beats NXDOMAIN here.
    script = ''
      current="$(cat ${mdnsHostsFile})"
      out="$current"
      for name in ${lib.escapeShellArgs mdnsMirrorNames}; do
        ip=$(avahi-resolve -4 -n "$name.local" 2>/dev/null | cut -f2)
        [ -n "$ip" ] || continue
        line="$ip $name.local"
        if printf '%s\n' "$current" | grep -q " $name\.local$"; then
          out=$(printf '%s\n' "$out" | sed "s/^.* $name\.local$/$line/")
        else
          out=$(printf '%s\n%s' "$out" "$line")
        fi
      done
      out=$(printf '%s\n' "$out" | sed '/^$/d')
      if [ "$out" != "$current" ]; then
        printf '%s\n' "$out" > ${mdnsHostsFile}
      fi
    '';
  };

  systemd.timers.mdns-pihole-mirror = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "2min";
    };
  };
}
