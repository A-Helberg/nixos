{ config, pkgs, lib, ... }:
let
  domain = "llm.coded.page";
  envFile = "/var/lib/hydra-secrets/litellm.env";
  presidioTag = "2.2.362";

  # Deterministic backstop for secrets: real API keys are almost always
  # pattern-shaped, and regexes never get tired halfway through a sentence.
  # Feeds presidio's analyzer as ad-hoc recognizers; matches surface as the
  # API_KEY entity and are MASKed.
  presidioAdHocRecognizers = pkgs.writeText "presidio-adhoc-recognizers.json" (builtins.toJSON [
    {
      name = "api-key-recognizer";
      supported_language = "en";
      supported_entity = "API_KEY";
      context = [ "key" "token" "secret" "credential" "password" "api" ];
      patterns = [
        { name = "dash-prefixed key (sk-/pk-/rk-)"; regex = "\\b(?:sk|pk|rk)-[A-Za-z0-9_-]{6,}\\b"; score = 0.6; }
        { name = "github/npm style token"; regex = "\\b(?:ghp|gho|ghu|ghs|github_pat|npm)_[A-Za-z0-9_]{8,}\\b"; score = 0.8; }
        { name = "gitlab token"; regex = "\\bglpat-[A-Za-z0-9_-]{8,}\\b"; score = 0.8; }
        { name = "slack token"; regex = "\\bxox[baprs]-[A-Za-z0-9-]{8,}\\b"; score = 0.8; }
        { name = "aws access key id"; regex = "\\b(?:AKIA|ASIA)[0-9A-Z]{16}\\b"; score = 0.8; }
        { name = "google api key"; regex = "\\bAIza[0-9A-Za-z_-]{30,}\\b"; score = 0.8; }
        { name = "jwt"; regex = "\\beyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{5,}\\b"; score = 0.8; }
        { name = "bearer header"; regex = "(?i)\\bbearer\\s+[A-Za-z0-9._~+/=-]{16,}"; score = 0.6; }
        { name = "pem private key"; regex = "-----BEGIN [A-Z ]*PRIVATE KEY-----"; score = 1.0; }
      ];
    }
  ]);

  # Outbound audit logger. (Until 2026-09 this module also held an
  # LLM-scrub guardrail backed by a claude-code-api proxy on :8377; that
  # second sanitisation stage was dropped — Presidio above is the only
  # pre-call scrubbing now.)
  auditPy = pkgs.writeText "llm_audit.py" ''
    import os
    from datetime import datetime

    import litellm
    from litellm.integrations.custom_logger import CustomLogger

    AUDIT_LOG = os.environ.get("AUDIT_LOG", "/var/lib/litellm/outbound-audit.log")


    def _render_content(content):
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            out = []
            for part in content:
                if isinstance(part, dict) and part.get("type") == "text":
                    out.append(str(part.get("text", "")))
                else:
                    ptype = part.get("type", "?") if isinstance(part, dict) else "?"
                    out.append(f"[non-text part: {ptype}]")
            return "\n".join(out)
        return repr(content)

    class OutboundAudit(CustomLogger):
        """Append every provider-bound payload to a local audit log.

        Fires at the last hop before the wire, after all guardrails have
        mutated the request - what lands here is exactly what the provider
        receives. Calls that stay on the LAN (LM Studio on phoenix) are
        tagged LAN-LOCAL.
        """

        def log_pre_api_call(self, model, messages, kwargs):
            try:
                params = kwargs.get("litellm_params") or {}
                base = params.get("api_base") or ""
                tag = " [LAN-LOCAL]" if "phoenix" in base else ""
                ts = datetime.now().isoformat(timespec="seconds")
                lines = [f"==== {ts} model={model} base={base or 'default'}{tag}"]
                for m in messages or []:
                    if isinstance(m, dict):
                        lines.append(f"-- {m.get('role', '?')}:")
                        lines.append(_render_content(m.get("content")))
                with open(AUDIT_LOG, "a") as f:
                    f.write("\n".join(lines) + "\n\n")
            except Exception as e:
                litellm._logging.verbose_proxy_logger.warning(
                    "outbound-audit: failed to write audit log: %s", e
                )

    audit = OutboundAudit()
  '';

  # litellm resolves a custom callback's module *relative to the directory
  # of config.yaml* (get_instance_fn), so the generated config and the
  # audit module must live side by side; the stock NixOS module puts the
  # yaml alone in the store, hence the ExecStart override below.
  configDir = pkgs.linkFarm "litellm-config" [
    {
      name = "config.yaml";
      path = (pkgs.formats.yaml { }).generate "litellm-config.yaml" config.services.litellm.settings;
    }
    {
      name = "llm_audit.py";
      path = auditPy;
    }
  ];
  cfg = config.services.litellm;

  # Dry-run the sanitisation: show what a prompt looks like after the
  # presidio guardrail, without calling any provider. Run as root (to
  # read the master key) or with LITELLM_MASTER_KEY set.
  #   llm-sanitize "Contact sarah.connor@skynet.io about hydra-db.lan"
  #   echo "text" | llm-sanitize
  llmSanitize = pkgs.writeShellApplication {
    name = "llm-sanitize";
    runtimeInputs = [ pkgs.curl pkgs.jq pkgs.gnugrep ];
    text = ''
      text="''${1:-$(cat)}"
      base="''${LITELLM_BASE:-http://127.0.0.1:4000}"
      key="''${LITELLM_MASTER_KEY:-}"
      if [ -z "$key" ] && [ -r /var/lib/hydra-secrets/litellm.env ]; then
        key=$(grep -oP '^LITELLM_MASTER_KEY=\K.*' /var/lib/hydra-secrets/litellm.env || true)
      fi
      if [ -z "$key" ]; then
        echo "no master key: run as root or set LITELLM_MASTER_KEY" >&2
        exit 1
      fi

      apply() {
        curl -sS "$base/guardrails/apply_guardrail" \
          -H "Authorization: Bearer $key" -H "Content-Type: application/json" \
          --data "$(jq -n --arg g "$1" --arg t "$2" '{guardrail_name: $g, text: $t}')"
      }

      echo "== original:"
      printf '%s\n\n' "$text"

      r=$(apply presidio-pii "$text")
      masked=$(printf '%s' "$r" | jq -r '.response_text // empty')
      if [ -z "$masked" ]; then
        echo "== presidio-pii: request would be REJECTED:"
        printf '%s\n' "$r" | jq .
        exit 0
      fi
      echo "== after presidio-pii (this is what leaves the LAN):"
      printf '%s\n' "$masked"
    '';
  };
in
{
  # ---------------------------------------------------------
  # LiteLLM proxy: one OpenAI-compatible endpoint in front of
  # Anthropic/OpenAI/Gemini/OpenRouter, so agents and
  # tools on the LAN get a single base URL, never hold real
  # provider keys — and every prompt is sanitised before it
  # leaves the LAN by a default-on pre-call stage:
  #
  #   Presidio (analyzer+anonymizer containers below): NER-based
  #   PII masking, plus ad-hoc regex recognizers for API keys.
  #   Masked values are restored in the response (output_parse_pii),
  #   so clients still get usable answers. Credit card numbers block
  #   the request outright.
  #
  #   (A second, LLM-based scrub stage backed by a claude-code-api
  #   proxy existed until 2026-09 — see git history if it's ever
  #   wanted back.)
  #
  #   Base URL: https://llm.coded.page/  (LAN; needs a Cloudflare
  #   DNS record llm.coded.page -> 10.253.10.2, like the others.)
  #   Admin UI: https://llm.coded.page/ui  (log in with master key)
  #
  # Clients authenticate with the master key as their API key and
  # address models as "<provider>/<model>", e.g.
  # "anthropic/claude-sonnet-4-5" — the wildcard routes below pass
  # them through. Only providers whose API key is present in the
  # env file will work.
  #
  # /var/lib/hydra-secrets/litellm.env must exist (0600 root) with:
  #   LITELLM_MASTER_KEY=sk-<openssl rand -hex 32>
  #   ANTHROPIC_API_KEY=...
  #   OPENAI_API_KEY=...          (optional)
  #   GEMINI_API_KEY=...          (optional)
  #   OPENROUTER_API_KEY=...      (optional)
  #
  # Runs without postgres: plain proxying + master-key auth only.
  # Virtual keys / per-key spend tracking would need a DATABASE_URL
  # and a postgres instance — add if ever needed.
  # Logs: journalctl -u litellm.
  #
  # Audit: every provider-bound payload (post-guardrails, i.e. exactly
  # what leaves) is appended to /var/lib/litellm/outbound-audit.log.
  # Review with:  sudo less +G /var/lib/litellm/outbound-audit.log
  # Entries tagged LAN-LOCAL never left the LAN (LM Studio on
  # phoenix). Rotated weekly, 8 kept.
  #
  # Interactive preview:  sudo llm-sanitize "some text with PII"
  # shows the text after presidio without calling any provider
  # (POST /guardrails/apply_guardrail under the hood).
  # ---------------------------------------------------------
  services.litellm = {
    enable = true;
    host = "127.0.0.1";
    port = 4000;
    environmentFile = envFile;
    settings = {
      model_list = [
        {
          model_name = "anthropic/*";
          litellm_params.model = "anthropic/*";
        }
        {
          model_name = "openai/*";
          litellm_params.model = "openai/*";
        }
        {
          model_name = "gemini/*";
          litellm_params.model = "gemini/*";
        }
        # Aggregator for the open-weight labs (DeepSeek, Qwen, Kimi, GLM,
        # ...): one key, models addressed as
        # "openrouter/<lab>/<model>", e.g. "openrouter/deepseek/deepseek-chat".
        {
          model_name = "openrouter/*";
          litellm_params.model = "openrouter/*";
        }
        # The wildcard routes ANY openrouter model, but /v1/models (what
        # Open WebUI's picker shows) only lists models from litellm's
        # built-in registry, frozen at the packaged litellm version.
        # Models newer than that need an explicit entry to be listed:
        {
          model_name = "openrouter/deepseek/deepseek-v4-flash";
          litellm_params.model = "openrouter/deepseek/deepseek-v4-flash";
        }
        {
          model_name = "openrouter/deepseek/deepseek-v4-flash-0731";
          litellm_params.model = "openrouter/deepseek/deepseek-v4-flash-0731";
        }
        # LM Studio models on phoenix, callable directly. LAN-local;
        # Presidio still masks, which is cheap and keeps PII out of
        # LM Studio's logs.
        {
          model_name = "phoenix/qwen3-vl-4b";
          litellm_params = {
            model = "lm_studio/qwen/qwen3-vl-4b";
            api_base = "http://phoenix.local:1234/v1";
            api_key = "none"; # LM Studio ignores it, litellm wants one set
          };
        }
        {
          model_name = "phoenix/qwen3.5-9b";
          litellm_params = {
            model = "lm_studio/qwen3.5-9b";
            api_base = "http://phoenix.local:1234/v1";
            api_key = "none";
          };
        }
      ];
      guardrails = [
        {
          guardrail_name = "presidio-pii";
          litellm_params = {
            guardrail = "presidio";
            mode = "pre_call";
            default_on = true;
            output_parse_pii = true;
            presidio_ad_hoc_recognizers = "${presidioAdHocRecognizers}";
            pii_entities_config = {
              CREDIT_CARD = "BLOCK";
              PERSON = "MASK";
              EMAIL_ADDRESS = "MASK";
              PHONE_NUMBER = "MASK";
              IP_ADDRESS = "MASK";
              IBAN_CODE = "MASK";
              API_KEY = "MASK"; # ad-hoc regex recognizers above
            };
          };
        }
      ];
      general_settings.master_key = "os.environ/LITELLM_MASTER_KEY";
      litellm_settings = {
        callbacks = [ "llm_audit.audit" ]; # outbound audit log, see llm_audit.py
        drop_params = true; # drop provider-unsupported params instead of erroring
        # Keep prompt content and keys out of litellm's own logs/tracebacks.
        redact_messages_in_exceptions = true;
        redact_user_api_key_info = true;
      };
    };
    # Defining `environment` replaces the module's default, so the
    # telemetry opt-outs are repeated here.
    environment = {
      SCARF_NO_ANALYTICS = "True";
      DO_NOT_TRACK = "True";
      ANONYMIZED_TELEMETRY = "False";
      PRESIDIO_ANALYZER_API_BASE = "http://127.0.0.1:5002";
      PRESIDIO_ANONYMIZER_API_BASE = "http://127.0.0.1:5001";
      # aiohttp's c-ares resolver queries resolv.conf's servers (1.1.1.1)
      # directly, so phoenix.local can never resolve through it. This forces
      # the httpx transport, which uses glibc's resolver and therefore
      # avahi/nss-mdns like every other process on hydra.
      DISABLE_AIOHTTP_TRANSPORT = "True";
    };
  };

  systemd.services.litellm = {
    # Don't come up half-configured if the secrets file is missing.
    unitConfig.ConditionPathExists = envFile;
    # Soft ordering only — litellm talks to presidio per-request, not at boot.
    after = [ "docker-presidio-analyzer.service" "docker-presidio-anonymizer.service" ];
    wants = [ "docker-presidio-analyzer.service" "docker-presidio-anonymizer.service" ];
    # Same flags as the stock module, but --config points into configDir so
    # llm_audit.py sits next to config.yaml (see note above).
    serviceConfig.ExecStart = lib.mkForce
      "${lib.getExe cfg.package} --host \"${cfg.host}\" --port ${toString cfg.port} --config ${configDir}/config.yaml";
  };

  environment.systemPackages = [ llmSanitize ];

  # The audit log lives in litellm's StateDirectory (owned by its dynamic
  # user); copytruncate so rotation never needs to touch ownership.
  services.logrotate.settings."/var/lib/litellm/outbound-audit.log" = {
    frequency = "weekly";
    rotate = 8;
    copytruncate = true;
    missingok = true;
    notifempty = true;
  };

  # Presidio PII services (backend is docker globally on hydra, set in
  # homebridge.nix). Loopback-only: nothing else should reach them, and
  # docker's published ports bypass the NixOS firewall anyway.
  virtualisation.oci-containers.containers = {
    presidio-analyzer = {
      image = "mcr.microsoft.com/presidio-analyzer:${presidioTag}";
      ports = [ "127.0.0.1:5002:3000" ];
    };
    presidio-anonymizer = {
      image = "mcr.microsoft.com/presidio-anonymizer:${presidioTag}";
      ports = [ "127.0.0.1:5001:3000" ];
    };
  };

  services.nginx.virtualHosts."${domain}" = {
    forceSSL = true;
    useACMEHost = domain;
    locations."/" = {
      proxyPass = "http://127.0.0.1:4000";
      # Completions stream; don't buffer them, and allow slow models.
      extraConfig = ''
        proxy_read_timeout 900s;
        proxy_send_timeout 900s;
        proxy_buffering off;
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
