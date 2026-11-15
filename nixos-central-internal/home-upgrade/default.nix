# nixos-central upgrade for standalone homes (standalone.nix): install the
# latest central configuration (and private overlay) right away, as the daily
# home-manager-auto-upgrade does. Counterpart of modules/base/upgrade.nix.
{
  lib,
  writeShellApplication,
  coreutils,
  diffutils,
  nix,
  home-manager,
  nix-output-monitor,
  # Keeps the recorded NVIDIA driver in step with the host (nvidia-pin.nix).
  nvidia-pin,
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
    diffutils # cmp
    nix
    home-manager
    nix-output-monitor # build progress (build_with_progress)
    nvidia-pin
  ];
  text = ''
    usage() {
      echo "usage: nixos-central upgrade [--private]" >&2
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
              echo "This home has no private overlay (add one with: nixos-central private setup)." >&2
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
    # The configuration home-only.sh writes. Named explicitly so the build and
    # the switch below use the same one.
    user=''${USER:-$(id -un)}
    profile() {
      readlink "''${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/home-manager" ||
        readlink "/nix/var/nix/profiles/per-user/$USER/home-manager" || true
    }

    # nix writes the updated lock file before building, and the NVIDIA pin may
    # be rewritten; put both back if the upgrade fails before a new generation
    # was installed.
    lock=$flake/flake.lock
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    backup=$tmp/flake.lock
    cp "$lock" "$backup"
    cp "$flake/flake.nix" "$tmp/flake.nix"
    profile_before=$(profile)

    # Never fails; on problems it warns and keeps the recorded driver.
    nixos-central-nvidia-pin "$flake"

    ${builtins.readFile ../lib/build-progress.sh}

    # Build first (with live progress on a terminal), then switch to the
    # finished build: home-manager only evaluates again.
    if ! { nix flake update "''${inputs[@]}" --flake "$flake" --refresh &&
      build_with_progress "$tmp/home" "$flake#homeConfigurations.\"$user\".activationPackage" &&
      home-manager switch --flake "$flake#$user" ${lib.escapeShellArgs switchFlags}; }; then
      if [ "$(profile)" = "$profile_before" ]; then
        cp "$backup" "$lock"
        cmp -s "$tmp/flake.nix" "$flake/flake.nix" || cp "$tmp/flake.nix" "$flake/flake.nix"
        echo "Upgrade failed; nothing was changed." >&2
      else
        echo "Upgrade installed, but activating it failed (go back with: home-manager generations)." >&2
      fi
      exit 1
    fi

    echo
    echo "The latest update is active."

    # The system-wide GPU setup (/run/opengl-driver) must point to this home's
    # drivers, e.g. after the NVIDIA pin moved. It needs root: run it with sudo
    # on a terminal (the password prompt is the consent), else say how.
    # Prints "<drivers> <setup>", or nothing without GPU integration.
    # shellcheck disable=SC2016 # a Nix expression, not shell
    gpu=$(nix eval --raw "$flake#homeConfigurations.\"$user\".config.targets.genericLinux.gpu" \
      --apply 'g: if g.enable then "''${g.drivers} ''${g.setupPackage}/bin/non-nixos-gpu-setup" else ""' 2>/dev/null) || gpu=""
    if [ -n "$gpu" ]; then
      drivers=''${gpu%% *}
      setup=''${gpu#* }
      if [ "$(readlink /run/opengl-driver || true)" != "$drivers" ]; then
        echo
        if [ -t 0 ] && [ -t 1 ]; then
          echo "The GPU drivers changed; setting them up for the whole machine (needs sudo) ..."
          if ! sudo "$setup"; then
            echo "GPU setup did not run. Programs from Nix may not find the GPU until you run:  sudo $setup" >&2
          fi
        else
          echo "The GPU drivers changed. To set them up for the whole machine, run:  sudo $setup"
        fi
      fi
    fi
  '';
}
