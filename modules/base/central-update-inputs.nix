# Flake inputs of /etc/nixos that upgrades update: `central` and, if the machine
# flake declares one, its private overlay (and nothing else). Shared by the
# daily auto-upgrade and nixos-central upgrade, which run
# `nix flake update <inputs>` before nixos-rebuild (nixos-rebuild's
# `--update-input` is deprecated).
config: [ "central" ] ++ (if config.nixos-central.private.enable then [ "private" ] else [ ])
