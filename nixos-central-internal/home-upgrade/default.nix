# nixos-central-upgrade for standalone homes (standalone.nix): install the
# latest central configuration (and private overlay) right away, as the daily
# home-manager-auto-upgrade does. Counterpart of modules/base/upgrade.nix.
{
  lib,
  writeShellApplication,
  coreutils,
  nix,
  home-manager,
  flakeDir,
  # Inputs the daily upgrade updates: central, plus private if declared.
  updateInputs,
  # home-manager switch flags of the daily upgrade.
  switchFlags,
}:
let
  hasPrivate = builtins.elem "private" updateInputs;
in
writeShellApplication {
  name = "nixos-central-upgrade";
  # No systemd: systemctl comes from the host, matching its user manager.
  runtimeInputs = [
    coreutils
    nix
    home-manager
  ];
  text = ''
    usage() {
      echo "usage: nixos-central-upgrade [--private]" >&2
      echo "Installs the latest central configuration${lib.optionalString hasPrivate " and private overlay"} and uses it right away." >&2
      echo "  --private  update only the private overlay; central stays as it is" >&2
      exit 2
    }

    inputs=(${lib.escapeShellArgs updateInputs})
    case "$*" in
      "") ;;
      --private)
        ${
          if hasPrivate then
            "inputs=(private)"
          else
            ''
              echo "This home has no private overlay (add one with: nixos-central-private setup)." >&2
              exit 1
            ''
        }
        ;;
      *) usage ;;
    esac

    # A running oneshot is "activating", which `systemctl is-active` reports as inactive.
    case "$(systemctl --user show --property=ActiveState --value home-manager-auto-upgrade.service 2>/dev/null || true)" in
      active | activating | reloading)
        echo "An automatic upgrade is running right now; try again when it has finished (journalctl --user -fu home-manager-auto-upgrade)." >&2
        exit 1
        ;;
    esac

    flake=${lib.escapeShellArg flakeDir}
    profile() {
      readlink "''${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/home-manager" ||
        readlink "/nix/var/nix/profiles/per-user/$USER/home-manager" || true
    }

    # nix writes the updated lock file before building; put it back if the
    # upgrade fails before a new generation was installed.
    lock=$flake/flake.lock
    backup=$(mktemp)
    trap 'rm -f "$backup"' EXIT
    cp "$lock" "$backup"
    profile_before=$(profile)

    if ! { nix flake update "''${inputs[@]}" --flake "$flake" --refresh &&
      home-manager switch --flake "$flake" ${lib.escapeShellArgs switchFlags}; }; then
      if [ "$(profile)" = "$profile_before" ]; then
        cp "$backup" "$lock"
        echo "Upgrade failed; nothing was changed." >&2
      else
        echo "Upgrade installed, but activating it failed (go back with: home-manager generations)." >&2
      fi
      exit 1
    fi

    echo
    echo "The latest update is active."
  '';
}
