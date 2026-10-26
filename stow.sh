#!/usr/bin/env bash

stow -d $HOME/nixos/ -t $HOME/.config .config

# Claude Code profiles (default plus the claude-* wrappers in zshrc)
for profile in .claude .claude-r .claude-i .claude-n; do
  mkdir -p "$HOME/$profile"
  stow -d $HOME/nixos/ -t "$HOME/$profile" .claude
done
