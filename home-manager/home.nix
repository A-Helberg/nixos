{ config, pkgs, ... }:
{
  imports = [
    ./common/base.nix
  ];

  home.packages = with pkgs; [
    obsidian
    realvnc-vnc-viewer
    slack
    asdf-vm
    rlwrap
    clojure
  ];

  programs.zsh.shellAliases = {
    rrun = ''f() { ssh 10.253.0.1 tmux new -d -s remote 2>/dev/null || true;
                    ssh 10.253.0.1 tmux send-keys -t remote.0 "'cd $PWD && clear'" ENTER "'$*'" ENTER "'read -s -k \"?Press any key to continue.\" && tmux detach'" ENTER
                    ssh -tt 10.253.0.1 tmux attach -t remote.0 };f'';
  };
}
