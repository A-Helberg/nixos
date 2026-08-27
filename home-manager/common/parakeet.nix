{ config, pkgs, ... }:
{
  # Speech-to-text API on the LAN: parakeet-mlx (0.6B, ~1.3GB RAM) behind an
  # OpenAI-compatible /v1/audio/transcriptions endpoint on port 9330. uv
  # resolves the script's inline deps into ~/.cache/uv on first launch and
  # the model downloads to ~/.cache/huggingface, so first start needs network
  # and a few minutes.
  launchd.agents.parakeet = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.uv}/bin/uv"
        "run"
        "--script"
        "${./parakeet-server.py}"
      ];
      EnvironmentVariables = {
        PATH = "${pkgs.ffmpeg}/bin:/usr/bin:/bin";
        PARAKEET_HOST = "0.0.0.0";
        PARAKEET_PORT = "9330";
      };
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/parakeet.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/parakeet.log";
    };
  };
}
