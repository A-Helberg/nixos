{ config, pkgs, ... }:
{
  system.stateVersion = 5;
  nixpkgs.hostPlatform = "aarch64-darwin";

  # Let Determinate Nix manage the daemon
  nix.enable = false;
  
  nix = {
    extraOptions = ''
      auto-optimise-store = true
      experimental-features = nix-command flakes
      extra-platforms = x86_64-darwin aarch64-darwin
    '';
    settings.experimental-features = "nix-command flakes";
  };

  system.activationScripts.applications.text = let
    env = pkgs.buildEnv {
      name = "system-applications";
      paths = config.environment.systemPackages;
      pathsToLink = [ "/Applications" ];
    };
  in pkgs.lib.mkForce ''
    echo "setting up /Applications..." >&2
    rm -rf /Applications/Nix\ Apps
    mkdir -p /Applications/Nix\ Apps
    find ${env}/Applications -maxdepth 1 -type l -exec readlink '{}' + |
    while read -r src; do
      app_name=$(basename "$src")
      echo "copying $src" >&2
      ${pkgs.mkalias}/bin/mkalias "$src" "/Applications/Nix Apps/$app_name"
    done
  '';

  # /etc/zshrc's global compinit runs before ~/.zshrc, so agent's `compinit -i`
  # never gets a chance: compaudit rejects Homebrew's andre-owned site-functions
  # for any other user and aborts the login shell. Every user's home-manager
  # zshrc runs its own compinit, so the global one is redundant anyway.
  programs.zsh.enableCompletion = false;

  # Per-user preferences (trackpad, dock, finder, key repeat, etc.) live in
  # home-manager/common/macos-defaults.nix so every GUI user gets them, not
  # just system.primaryUser. Only genuinely system-scoped defaults stay here.
  system.defaults = {
    loginwindow.GuestEnabled = false;
  };

  environment.systemPackages = with pkgs; [
    mkalias
    nh
  ];

  homebrew = {
    enable = true;
    onActivation.autoUpdate = true;
    onActivation.cleanup = "zap";

    brews = [
      "mas"
      "tailscale"
      "iproute2mac"
      "websocat"
      "lima"
      "llama.cpp"
      "gitui"
      # babashka/bbin/packer live in non-official taps and are formulae (not casks).
      # nix-darwin defaults `trusted = true` for brews, so they're trusted automatically
      # despite Homebrew 6.0's HOMEBREW_REQUIRE_TAP_TRUST.
      "hashicorp/tap/packer"
      "borkdude/brew/babashka"
      "babashka/brew/bbin"
    ];

    casks = [
      "hashicorp/tap/hashicorp-vagrant"
      # Development
      "jetbrains-toolbox"
      "visual-studio-code"
      "ghostty"
      "claude-code"
    ] ++ pkgs.lib.optionals (config.networking.hostName != "phoenix") [
      "orbstack"
    ] ++ [

      # Browsers
      "firefox"
      "chromium"
      "arc"
      "choosy"
      #"responsively"

      # Productivity
      "1password"
      "obsidian"
      "iina"
      "the-unarchiver"

      # Power User
      "karabiner-elements"
      "leader-key"
      "hammerspoon"
      #"raycast"

      # Security
      "little-snitch"
    ];

    masApps = {
      #"Slack" = 803453959;
      #"1Password for Safari" = 1569813296;
      #"Amphetamine" = 937984704;
    };
  };
}

