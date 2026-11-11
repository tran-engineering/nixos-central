# build_with_progress <out-link> <nix build arguments...>
#
# Builds with `nix build`, leaving the result at <out-link>. On a terminal the
# build is shown with nix-output-monitor's live display; otherwise (serial
# console, TERM=dumb, output redirected, NIXOS_CENTRAL_PLAIN set, or nom not
# on PATH) with Nix's plain log lines. Fails when the build fails, whatever nom
# returns (callers run with pipefail).
#
# Inlined into modules/base/upgrade.nix and nixos-central-internal/home-upgrade.
# install.sh and home-only.sh are published standalone and carry their own
# copies; keep them in step.
build_with_progress() {
  local link=$1
  shift
  if [ -z "${NIXOS_CENTRAL_PLAIN:-}" ] && [ -t 2 ] && command -v nom >/dev/null; then
    case "${TERM:-dumb}" in
      dumb | unknown) ;;
      *)
        nix build "$@" --out-link "$link" --log-format internal-json -v 2>&1 | nom --json
        return
        ;;
    esac
  fi
  # TERM=dumb: Nix's line logger, as on a serial console, also when this is a
  # terminal (no progress bar redraws). `--log-format raw` drops Nix's messages.
  TERM=dumb nix build "$@" --out-link "$link"
}
