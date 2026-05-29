{ pkgs, ... }:
let
  nexusDomain = "cache.coded.page";
  bridgeIp = "10.200.0.1";

  # Idempotent provisioning script: creates repos and enables anonymous access
  # via the Nexus REST API. Skips if already provisioned.
  #
  # PREREQUISITE: Before running this script, create a cleanup policy named
  # "30d-unused" in the Nexus UI (Admin → Cleanup Policies) with criterion:
  #   "Last Downloaded Before" = 30 days
  # The Cleanup Policies REST API is Nexus Pro only, so this one step is manual.
  # Nexus's built-in daily "Cleanup repositories using their associated policies"
  # task will then apply it automatically.
  provisionScript = pkgs.writeShellScript "nexus-provision" ''
    set -euo pipefail

    STATE_FILE="/data/nexus/.provisioned"
    NEXUS_URL="http://localhost:8082"
    PASS_FILE="/var/lib/hydra-secrets/nexus-admin-password"

    # Wait for Nexus to become ready (up to 5 minutes)
    echo "Waiting for Nexus to be ready..."
    for i in $(seq 1 60); do
      if ${pkgs.curl}/bin/curl -sf "$NEXUS_URL/service/rest/v1/status" > /dev/null 2>&1; then
        echo "Nexus is ready."
        break
      fi
      if [ "$i" -eq 60 ]; then
        echo "ERROR: Nexus did not become ready in time."
        exit 1
      fi
      sleep 5
    done

    if [ -f "$STATE_FILE" ]; then
      echo "Nexus already provisioned, skipping."
      exit 0
    fi

    PASS=$(cat "$PASS_FILE")
    AUTH="-u admin:$PASS"

    api() {
      local method=$1; shift
      local url=$1; shift
      local response http_code body
      response=$(${pkgs.curl}/bin/curl -s -w "\n%{http_code}" -X "$method" $AUTH \
        -H "Content-Type: application/json" \
        "$url" "$@")
      http_code=$(echo "$response" | tail -1)
      body=$(echo "$response" | head -n -1)
      if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        echo "$body"
        return 0
      else
        echo "ERROR $http_code: $body" >&2
        return 1
      fi
    }

    # maven-central already exists as a Nexus default with the correct upstream.
    # Skip creation and just update maven-public to include clojars.

    echo "Creating Clojars proxy repo..."
    api POST "$NEXUS_URL/service/rest/v1/repositories/maven/proxy" -d '{
      "name": "clojars",
      "online": true,
      "storage": { "blobStoreName": "default", "strictContentTypeValidation": true },
      "cleanup": { "policyNames": ["30d-unused"] },
      "proxy": { "remoteUrl": "https://repo.clojars.org/", "contentMaxAge": 1440, "metadataMaxAge": 1440 },
      "negativeCache": { "enabled": true, "timeToLive": 1440 },
      "httpClient": { "blocked": false, "autoBlock": true },
      "maven": { "versionPolicy": "MIXED", "layoutPolicy": "PERMISSIVE" }
    }' || echo "clojars creation failed (see error above), continuing..."

    echo "Updating maven-public group to include clojars..."
    api PUT "$NEXUS_URL/service/rest/v1/repositories/maven/group/maven-public" -d '{
      "name": "maven-public",
      "online": true,
      "storage": { "blobStoreName": "default", "strictContentTypeValidation": true },
      "group": {
        "memberNames": ["maven-central", "maven-releases", "maven-snapshots", "clojars"]
      },
      "maven": { "versionPolicy": "MIXED", "layoutPolicy": "PERMISSIVE" }
    }' || echo "maven-public update failed (see error above), continuing..."

    echo "Creating npm proxy repo..."
    api POST "$NEXUS_URL/service/rest/v1/repositories/npm/proxy" -d '{
      "name": "npm-proxy",
      "online": true,
      "storage": { "blobStoreName": "default", "strictContentTypeValidation": true },
      "cleanup": { "policyNames": ["30d-unused"] },
      "proxy": { "remoteUrl": "https://registry.npmjs.org", "contentMaxAge": 1440, "metadataMaxAge": 1440 },
      "negativeCache": { "enabled": true, "timeToLive": 1440 },
      "httpClient": { "blocked": false, "autoBlock": true },
      "npmProxy": { "removeNonCataloged": false }
    }' || echo "npm-proxy creation failed (see error above), continuing..."

    echo "Creating apt proxy repo (Ubuntu 24.04 noble — archive.ubuntu.com)..."
    api POST "$NEXUS_URL/service/rest/v1/repositories/apt/proxy" -d '{
      "name": "apt-proxy",
      "online": true,
      "storage": { "blobStoreName": "default", "strictContentTypeValidation": true },
      "cleanup": { "policyNames": ["30d-unused"] },
      "proxy": { "remoteUrl": "http://archive.ubuntu.com/ubuntu/", "contentMaxAge": 1440, "metadataMaxAge": 1440 },
      "negativeCache": { "enabled": true, "timeToLive": 1440 },
      "httpClient": { "blocked": false, "autoBlock": true },
      "apt": { "distribution": "noble", "flat": false },
      "aptSigning": { "keypair": "", "passphrase": "" }
    }' || echo "apt-proxy creation failed (see error above), continuing..."

    echo "Creating apt security proxy repo (Ubuntu 24.04 noble — security.ubuntu.com)..."
    api POST "$NEXUS_URL/service/rest/v1/repositories/apt/proxy" -d '{
      "name": "apt-security",
      "online": true,
      "storage": { "blobStoreName": "default", "strictContentTypeValidation": true },
      "cleanup": { "policyNames": ["30d-unused"] },
      "proxy": { "remoteUrl": "http://security.ubuntu.com/ubuntu/", "contentMaxAge": 1440, "metadataMaxAge": 1440 },
      "negativeCache": { "enabled": true, "timeToLive": 1440 },
      "httpClient": { "blocked": false, "autoBlock": true },
      "apt": { "distribution": "noble", "flat": false },
      "aptSigning": { "keypair": "", "passphrase": "" }
    }' || echo "apt-security creation failed (see error above), continuing..."

    echo "Enabling anonymous access..."
    api PUT "$NEXUS_URL/service/rest/v1/security/anonymous" -d '{
      "enabled": true,
      "userId": "anonymous",
      "realmName": "NexusAuthorizingRealm"
    }'

    touch "$STATE_FILE"
    echo "Nexus provisioning complete."
  '';
in
{
  # Run Nexus via Docker to get the latest upstream version rather than the
  # outdated/insecure nixpkgs package. All state lives on the fast /data NVMe.
  virtualisation.oci-containers.containers.nexus = {
    image = "sonatype/nexus3:latest";
    ports = [ "127.0.0.1:8082:8081" ];
    volumes = [ "/data/nexus:/nexus-data" ];
    environment = {
      # Give Nexus a generous heap; the machine has plenty of RAM.
      INSTALL4J_ADD_VM_PARAMS = "-Xms2g -Xmx4g -XX:MaxDirectMemorySize=3g";
    };
  };

  # The Nexus container runs as UID 200 internally.
  systemd.tmpfiles.rules = [
    "d /data/nexus 0750 200 200 -"
  ];

  # Idempotent provisioning: runs once after the container is healthy, then
  # marks itself done via a state file so it doesn't re-run on every boot.
  systemd.services.nexus-provision = {
    description = "Provision Nexus repositories and cleanup policies";
    after = [ "docker-nexus.service" ];
    wants = [ "docker-nexus.service" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "/var/lib/hydra-secrets/nexus-admin-password";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${provisionScript}";
    };
  };

  # Allow VMs on the bridge to reach Nexus directly over HTTPS via nginx.
  networking.firewall.interfaces.fireactions0.allowedTCPPorts = [ 8082 ];
}
