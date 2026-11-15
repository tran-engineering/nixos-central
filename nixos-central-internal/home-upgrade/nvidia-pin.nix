# Keeps the NVIDIA driver recorded in a standalone home's flake (the `nvidia = …;`
# line home-only.sh writes) in step with the driver loaded on the host, so Nix
# programs keep matching the kernel module after the distribution updates it.
# Used by `nixos-central upgrade` and the daily home-manager-auto-upgrade before
# they build. Never fails: every problem is a warning and the old pin stays.
# NIXOS_CENTRAL_NVIDIA_* are only set by tests.
{
  writeShellApplication,
  coreutils,
  gnugrep,
  gnused,
  nix,
}:
writeShellApplication {
  name = "nixos-central-nvidia-pin";
  runtimeInputs = [
    coreutils
    gnugrep
    gnused
    nix
  ];
  text = ''
    if [ $# -ne 1 ]; then
      echo "usage: nixos-central-nvidia-pin <flake-dir>" >&2
      exit 2
    fi
    flake=$1/flake.nix
    version_file=''${NIXOS_CENTRAL_NVIDIA_VERSION_FILE:-/proc/driver/nvidia/version}
    base_url=''${NIXOS_CENTRAL_NVIDIA_BASE_URL:-https://download.nvidia.com/XFree86}
    warn() { echo "Warning: $*" >&2; }

    # Version pattern as in home-only.sh and home-manager's gpu.nvidia.version.
    version_re='[0-9]{3}\.[0-9]{2,3}(\.[0-9]{2,3})?'

    # No NVIDIA driver loaded: nothing to follow.
    [ -r "$version_file" ] || exit 0
    loaded=$(head -n1 "$version_file" | grep -oE "$version_re" | head -n1 || true)
    [ -n "$loaded" ] || exit 0
    [ -r "$flake" ] || exit 0

    # The installer's line: `nvidia = null;` or
    # `nvidia = { version = "…"; sha256 = "…"; };`, with an optional comment.
    null_re='^[[:space:]]*nvidia = null;'
    pin_re='^[[:space:]]*nvidia = \{ version = "[^"]*"; sha256 = "[^"]*"; \};'
    if [ "$(grep -cE '^[[:space:]]*nvidia =' "$flake" || true)" -eq 1 ]; then
      grep -qE "$null_re" "$flake" && exit 0
      if grep -qE "$pin_re" "$flake"; then
        pinned=$(grep -E "$pin_re" "$flake" | sed -E 's/.*version = "([^"]*)".*/\1/')
        [ "$pinned" = "$loaded" ] && exit 0

        case "$(uname -m)" in
          aarch64 | arm64) arch=aarch64 ;;
          *) arch=x86_64 ;;
        esac
        url="$base_url/Linux-$arch/$loaded/NVIDIA-Linux-$arch-$loaded.run"
        echo "NVIDIA driver $loaded is loaded, but the home uses $pinned; fetching it (this may take a while) ..." >&2
        if ! hash=$(nix store prefetch-file --json "$url" | sed -n 's/.*"hash": *"\([^"]*\)".*/\1/p') || [ -z "$hash" ]; then
          warn "could not download NVIDIA driver $loaded ($url); keeping $pinned. Programs from Nix may not find the GPU until it can be fetched."
          exit 0
        fi
        # Only the two quoted values change; indentation and comment stay.
        sed -i -E "/$pin_re/ s|version = \"[^\"]*\"; sha256 = \"[^\"]*\";|version = \"$loaded\"; sha256 = \"$hash\";|" "$flake"
        echo "NVIDIA driver $pinned -> $loaded" >&2
        exit 0
      fi
    fi

    # A driver is loaded, but the line is not in the installer's shape (or absent).
    grep -qE '^[[:space:]]*nvidia =' "$flake" || exit 0
    warn "$flake does not record the NVIDIA driver in the expected form; set nvidia = { version = \"$loaded\"; sha256 = \"…\"; }; by hand (see the README, \"GPU drivers\")."
  '';
}
