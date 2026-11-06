# nixos-central private: show, add or remove the private overlay of this
# machine (/etc/nixos) or standalone home (~/.config/home-manager). See the
# README, "Private overlay". GITHUB_HOST_KEY, DEFAULT_URL and flake-edit.sh
# (flake_add_overlay, flake_remove_overlay) are prepended when packaged.

info() { printf '%s\n' "$*" >&2; }
die() {
  printf '\n\033[1;31mError:\033[0m %s\n' "$*" >&2
  exit 1
}

usage_text() {
  cat <<EOF
Usage: nixos-central private          show the private overlay
       nixos-central private setup [<flake-url>] [--profile NAME]
                                      add the private overlay and activate it
       nixos-central private remove   remove it and activate the result

<flake-url>     the overlay's repository; default: $DEFAULT_URL
--profile NAME  use profile NAME (in the central repository and the overlay)
                instead of the recorded one, or of the user's name. On NixOS,
                remove takes the recorded profile out again.

Example: nixos-central private setup git+ssh://git@github.com/alice/private --profile developer
EOF
}

usage() {
  usage_text >&2
  exit 2
}

nixx() { nix --extra-experimental-features "nix-command flakes" "$@"; }

# MODE (nixos/home), DIR, FLAKE, KEY.
detect() {
  if [ -e /etc/NIXOS ] && [ -f /etc/nixos/flake.nix ]; then
    MODE=nixos DIR=/etc/nixos
    local user
    user=$(sed -n 's/^ *user = "\([^"]*\)";.*/\1/p' "$DIR/flake.nix" | head -n1)
    KEY="/home/${user:-<user>}/.ssh/id_ed25519"
  elif [ -f "$HOME/.config/home-manager/flake.nix" ]; then
    MODE=home DIR="$HOME/.config/home-manager"
    KEY="$HOME/.ssh/id_ed25519"
  else
    die "Neither /etc/nixos/flake.nix (NixOS) nor ~/.config/home-manager/flake.nix (standalone home) exists. Install nixos-central first."
  fi
  FLAKE="$DIR/flake.nix"
}

# Changes on NixOS need root: re-run with the same arguments.
become_root() {
  if [ "$MODE" = nixos ] && [ "$(id -u)" -ne 0 ]; then
    exec sudo "$0" "$@"
  fi
}

BACKUP=""
backup() {
  BACKUP=$(mktemp -d)
  cp "$FLAKE" "$BACKUP/flake.nix"
  [ ! -f "$DIR/flake.lock" ] || cp "$DIR/flake.lock" "$BACKUP/flake.lock"
}
restore() {
  [ -n "$BACKUP" ] || return 0
  cp "$BACKUP/flake.nix" "$FLAKE"
  [ ! -f "$BACKUP/flake.lock" ] || cp "$BACKUP/flake.lock" "$DIR/flake.lock"
  info "Restored $FLAKE and its lock file; nothing was changed."
}

activate() {
  if [ "$MODE" = nixos ]; then
    nixos-rebuild switch --flake "$DIR"
  else
    home-manager switch --flake "$DIR" -b backup
  fi
}

setup() {
  local url=$1 profile=${2:-}
  if [ -n "$profile" ]; then
    [[ $profile =~ ^[A-Za-z0-9._-]+$ ]] || die "Invalid profile name: $profile"
  fi
  flake_has_overlay "$FLAKE" && die "This configuration already has a private overlay. Remove it first: nixos-central private remove"

  if [ "$MODE" = home ]; then
    mkdir -p "$HOME/.ssh"
    grep -qsF "github.com $GITHUB_HOST_KEY" "$HOME/.ssh/known_hosts" ||
      printf 'github.com %s\n' "$GITHUB_HOST_KEY" >>"$HOME/.ssh/known_hosts"
  fi

  flake_check_overlay_anchors "$FLAKE" "$MODE" "$profile"

  info "Checking access to $url ..."
  local err
  if ! err=$(nixx flake metadata --refresh "$url" 2>&1 >/dev/null); then
    info "$err"
    die "Cannot read $url. Check the URL, and that the SSH key $KEY exists and is added to your GitHub account (https://github.com/settings/keys)."
  fi

  backup
  trap 'restore' ERR
  flake_add_overlay "$FLAKE" "$MODE" "$url" "$profile"

  info "Activating with the private overlay ..."
  activate
  trap - ERR
  info ""
  info "The private overlay is set up. Upgrades now update it together with the central repository."
}

show() {
  local url
  url=$(sed -n 's/^ *inputs\.private\.url = "\([^"]*\)";.*/\1/p' "$FLAKE" | head -n1)
  if [ -n "$url" ]; then
    echo "Private overlay: $url"
  else
    echo "No private overlay. Add one with: nixos-central private setup"
  fi
  echo
  usage_text
}

remove() {
  flake_has_overlay "$FLAKE" || die "This configuration has no private overlay."
  backup
  trap 'restore' ERR
  flake_remove_overlay "$FLAKE" "$MODE"
  info "Activating without the private overlay ..."
  activate
  trap - ERR
  info ""
  info "The private overlay is removed."
}

main() {
  set -Eeuo pipefail
  local url="" profile=""
  case "${1:-}" in
    "") ;;
    setup)
      # setup [<flake-url>] [--profile NAME]
      local rest=("${@:2}")
      if [ ${#rest[@]} -gt 0 ] && [ "${rest[0]}" != --profile ]; then
        url=${rest[0]}
        rest=("${rest[@]:1}")
      fi
      if [ ${#rest[@]} -eq 2 ] && [ "${rest[0]}" = --profile ]; then
        profile=${rest[1]}
      else
        [ ${#rest[@]} -eq 0 ] || usage
      fi
      ;;
    remove) [ $# -eq 1 ] || usage ;;
    *) usage ;;
  esac
  detect
  if [ $# -eq 0 ]; then
    show
    return
  fi
  become_root "$@"
  case "$1" in
    setup)
      if [ -z "$url" ]; then
        url=$DEFAULT_URL
        info "Using the default overlay $url"
      fi
      setup "$url" "$profile"
      ;;
    remove) remove ;;
  esac
}

main "$@"
