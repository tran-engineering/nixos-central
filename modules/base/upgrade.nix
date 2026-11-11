# nixos-central upgrade: install the latest central configuration right away.
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
      config.nix.package
      pkgs.coreutils
      config.systemd.package
      pkgs.nix-output-monitor # build progress (build_with_progress)
    ];
    text = ''
      update_inputs=(${lib.escapeShellArgs (import ./central-update-inputs.nix config)})
      case "$*" in
        "") ;;
        --private)
          ${
            if config.nixos-central.private.enable then
              "update_inputs=(private)"
            else
              ''
                echo "This machine has no private overlay (add one with: nixos-central private setup)." >&2
                exit 1
              ''
          }
          ;;
        *)
          echo "usage: nixos-central upgrade [--private]" >&2
          echo "Installs the latest ${config.nixos-central.repo} and uses it right away." >&2
          echo "  --private  update only the private overlay; central stays as it is" >&2
          exit 2
          ;;
      esac

      if [ "$(id -u)" -ne 0 ]; then
        # sudo resets the environment; keep what decides the build display.
        exec sudo env NIXOS_CENTRAL_PLAIN="''${NIXOS_CENTRAL_PLAIN:-}" TERM="''${TERM:-dumb}" "$0" "$@"
      fi

      # A running oneshot is "activating", which `systemctl is-active` reports as inactive.
      case "$(systemctl show --property=ActiveState --value nixos-upgrade.service)" in
        active | activating | reloading)
          echo "An automatic upgrade is running right now; try again when it has finished (journalctl -fu nixos-upgrade)." >&2
          exit 1
          ;;
      esac

      # The lock file is updated before building; put it back if the
      # upgrade fails before a new generation was installed.
      lock=/etc/nixos/flake.lock
      tmp=$(mktemp -d)
      trap 'rm -rf "$tmp"' EXIT
      backup=$tmp/flake.lock
      cp "$lock" "$backup"
      profile_before=$(readlink /nix/var/nix/profiles/system || true)

      ${builtins.readFile ../../nixos-central-internal/lib/build-progress.sh}

      # Build first (with live progress on a terminal), then switch to the
      # finished build: nixos-rebuild only evaluates again.
      if ! { nix flake update "''${update_inputs[@]}" --flake /etc/nixos --refresh &&
        build_with_progress "$tmp/system" ${lib.escapeShellArg "/etc/nixos#nixosConfigurations.\"${config.nixos-central.hostname}\".config.system.build.toplevel"} &&
        nixos-rebuild switch --flake "/etc/nixos#${config.nixos-central.hostname}"; }; then
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
      ${builtins.readFile ./upgrade-reboot-hint.sh}
    '';
  };
in
{
  nixos-central.commands.upgrade = (import ../../nixos-central-internal/command/subcommands.nix).upgrade // {
    package = upgrade;
  };
}
