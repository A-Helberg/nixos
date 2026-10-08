{ config, pkgs, lib, ... }:
let
  tunnel = "hydra-tunnel";
  credentialsFile = "/var/lib/hydra-secrets/cloudflare-tunnel.json";

  # Every ingress hostname, including routes other modules add.
  hostnames = lib.attrNames config.services.cloudflared.tunnels.${tunnel}.ingress;

  # Points each hostname at this tunnel: a proxied CNAME to
  # <tunnel-id>.cfargotunnel.com. Records of any other shape under that
  # name (another tunnel, an A/AAAA placeholder) are replaced. Never
  # deletes records for hostnames dropped from the ingress.
  dnsScript = pkgs.writeShellApplication {
    name = "cloudflared-dns";
    runtimeInputs = [ pkgs.curl pkgs.jq pkgs.gawk ];
    text = ''
      : "''${CF_DNS_API_TOKEN:?missing from the ACME env file}"
      api() {
        curl -sS --fail-with-body -H "Authorization: Bearer $CF_DNS_API_TOKEN" \
          -H "Content-Type: application/json" "$@"
      }
      base=https://api.cloudflare.com/client/v4

      target="$(jq -r .TunnelID ${credentialsFile}).cfargotunnel.com"

      for host in ${lib.escapeShellArgs hostnames}; do
        # Last two labels; fine for coded.page, not for e.g. co.uk zones.
        zone_name=$(awk -F. '{ print $(NF-1) "." $NF }' <<< "$host")
        zone=$(api "$base/zones?name=$zone_name" | jq -r '.result[0].id')
        records=$(api "$base/zones/$zone/dns_records?name=$host" | jq -c '.result')

        if jq -e --arg t "$target" \
          'length == 1 and .[0].type == "CNAME" and .[0].content == $t and .[0].proxied' \
          <<< "$records" > /dev/null; then
          continue
        fi

        for id in $(jq -r '.[].id' <<< "$records"); do
          echo "$host: removing $(jq -r --arg id "$id" '.[] | select(.id == $id) | "\(.type) \(.content)"' <<< "$records")"
          api -X DELETE "$base/zones/$zone/dns_records/$id" > /dev/null
        done
        echo "$host: CNAME $target"
        api -X POST "$base/zones/$zone/dns_records" --data "$(jq -nc --arg name "$host" --arg t "$target" \
          '{ type: "CNAME", name: $name, content: $t, proxied: true, comment: "${tunnel} (nix)" }')" > /dev/null
      done
    '';
  };
in
{
  services.cloudflared = {
    enable = true;
    tunnels = {
      "${tunnel}" = {
        inherit credentialsFile;
        default = "http_status:404";
        ingress = {
          # Route external traffic to Nexus (Maven/npm/apt cache)
          "cache.coded.page" = "http://127.0.0.1:8082";
        };
      };
    };
  };

  # Re-runs whenever the hostname list changes (the script is rebuilt).
  systemd.services.cloudflared-dns = {
    description = "Point ${tunnel}'s hostnames at it in Cloudflare DNS";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # CF_DNS_API_TOKEN, shared with ACME (DNS edit on the zone).
      EnvironmentFile = "/var/lib/hydra-secrets/cloudflare-acme.env";
      ExecStart = lib.getExe dnsScript;
    };
  };
}
