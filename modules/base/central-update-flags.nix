# nixos-rebuild flags that update the machine's `central` input and, if the
# machine flake declares one, its private overlay (and nothing else). Shared by
# the daily auto-upgrade and nixos-central-upgrade.
config:
[
  "--update-input"
  "central"
]
++ (if config.nixos-central.private.enable then [ "--update-input" "private" ] else [ ])
