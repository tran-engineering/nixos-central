# nixos-central-upgrade: install the latest central configuration right away.
# Same update as the daily auto-upgrade, but activated now (switch) instead of
# only staged for the next boot. Never reboots.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  upgrade = pkgs.writeShellApplication {
    name = "nixos-central-upgrade";
    runtimeInputs = [
      config.system.build.nixos-rebuild
      pkgs.coreutils
      config.systemd.package
    ];
    text = ''
      update_flags=(${lib.escapeShellArgs (import ./central-update-flags.nix config)})
      case "$*" in
        "") ;;
        --private)
          ${
            if config.nixos-central.private.enable then
              "update_flags=(--update-input private)"
            else
              ''
                echo "This machine has no private overlay (add one with: nixos-central-private setup)." >&2
                exit 1
              ''
          }
          ;;
        *)
          echo "usage: nixos-central-upgrade [--private]" >&2
          echo "Installs the latest ${config.nixos-central.repo} and uses it right away." >&2
          echo "  --private  update only the private overlay; central stays as it is" >&2
          exit 2
          ;;
      esac

      if [ "$(id -u)" -ne 0 ]; then
        exec sudo "$0" "$@"
      fi

      # A running oneshot is "activating", which `systemctl is-active` reports as inactive.
      case "$(systemctl show --property=ActiveState --value nixos-upgrade.service)" in
        active | activating | reloading)
          echo "An automatic upgrade is running right now; try again when it has finished (journalctl -fu nixos-upgrade)." >&2
          exit 1
          ;;
      esac

      # nix writes the updated lock file before building; put it back if the
      # upgrade fails before a new generation was installed.
      lock=/etc/nixos/flake.lock
      backup=$(mktemp)
      trap 'rm -f "$backup"' EXIT
      cp "$lock" "$backup"
      profile_before=$(readlink /nix/var/nix/profiles/system || true)

      if ! nixos-rebuild switch \
        --flake "/etc/nixos#${config.nixos-central.hostname}" \
        "''${update_flags[@]}" \
        --refresh; then
        if [ "$(readlink /nix/var/nix/profiles/system || true)" = "$profile_before" ]; then
          cp "$backup" "$lock"
          echo "Upgrade failed; nothing was changed." >&2
        else
          echo "Upgrade installed as the default boot entry, but activating it failed." >&2
        fi
        exit 1
      fi

      # Seen by the update notice (modules/home/update-notice.nix).
      mkdir -p /var/lib/nixos-central
      touch /var/lib/nixos-central/last-update

      echo
      echo "The latest update is active."
      if [ "$(readlink -f /run/booted-system/kernel)" != "$(readlink -f /run/current-system/kernel)" ]; then
        echo "The new kernel is used after the next reboot."
      fi
    '';
  };
in
{
  environment.systemPackages = [ upgrade ];
}
