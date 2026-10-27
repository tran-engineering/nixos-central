# nixos-central-private: add or remove the private overlay of this machine
# (/etc/nixos) or standalone home (~/.config/home-manager). See the README,
# "Private overlay". GITHUB_HOST_KEY is prepended when packaged.

info() { printf '%s\n' "$*" >&2; }
die() {
  printf '\n\033[1;31mError:\033[0m %s\n' "$*" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
Usage: nixos-central-private setup <flake-url> [--profile NAME]
                                          add the private overlay and activate it
       nixos-central-private remove       remove it and activate the result

--profile NAME  standalone homes only: use profile NAME (in the central
                repository and the overlay) instead of the recorded one.
                On NixOS the profile is always the primary user's name.

Example: nixos-central-private setup git+ssh://git@github.com/alice/private --profile alice
EOF
  exit 2
}

nixx() { nix --extra-experimental-features "nix-command flakes" "$@"; }
sed_escape() { printf '%s' "$1" | sed 's/[\\|&]/\\&/g'; }

# MODE (nixos/home), DIR, FLAKE, KEY; on NixOS re-run as root.
detect() {
  if [ -e /etc/NIXOS ] && [ -f /etc/nixos/flake.nix ]; then
    if [ "$(id -u)" -ne 0 ]; then
      exec sudo "$0" "$@"
    fi
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

has_overlay() { grep -q '^ *inputs\.private\.url' "$FLAKE"; }

# Exactly one line matching the pattern, or explain and stop.
require_anchor() {
  [ "$(grep -c "$1" "$FLAKE")" -eq 1 ] ||
    die "$FLAKE does not have the expected shape (looking for: $2). Edit it by hand as described in the README, \"Private overlay\"."
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
    [ "$MODE" = home ] || die "--profile is only for standalone homes; on NixOS the profile is the primary user's name."
    [[ $profile =~ ^[A-Za-z0-9._-]+$ ]] || die "Invalid profile name: $profile"
  fi
  has_overlay && die "This configuration already has a private overlay. Remove it first: nixos-central-private remove"

  if [ "$MODE" = home ]; then
    mkdir -p "$HOME/.ssh"
    grep -qsF "github.com $GITHUB_HOST_KEY" "$HOME/.ssh/known_hosts" ||
      printf 'github.com %s\n' "$GITHUB_HOST_KEY" >>"$HOME/.ssh/known_hosts"
  fi

  require_anchor '^ *inputs\.central\.url = ' 'inputs.central.url = ...;'
  require_anchor '{ *central, *\.\.\. *}:' '{ central, ... }:'
  # `inherit private;` goes into the mkHost/mkHome call, before this line.
  local before='^ *modules = \[' before_text='modules = [ ... ];'
  if [ "$MODE" = home ]; then
    before='^ *stateVersion = ' before_text='stateVersion = "...";'
  fi
  require_anchor "$before" "$before_text"
  [ -z "$profile" ] || require_anchor '^ *profile = "[^"]*";' 'profile = "...";'

  info "Checking access to $url ..."
  local err
  if ! err=$(nixx flake metadata --refresh "$url" 2>&1 >/dev/null); then
    info "$err"
    die "Cannot read $url. Check the URL, and that the SSH key $KEY exists and is added to your GitHub account (https://github.com/settings/keys)."
  fi

  backup
  trap 'restore' ERR
  local u
  u=$(sed_escape "$url")
  sed -i \
    -e "s|^\( *\)inputs\.central\.url = \(.*\)$|&\n\1inputs.private.url = \"$u\";|" \
    -e 's|{ *central, *\.\.\. *}:|{ central, private, ... }:|' \
    -e "s|\($before\)|inherit private;\n&|" \
    "$FLAKE"
  [ -z "$profile" ] ||
    sed -i "s|^\( *profile = \)\"[^\"]*\";.*$|\1\"$profile\"; # in the central repository or the private overlay|" "$FLAKE"
  # Indent `inherit private;` like the line after it.
  sed -i -e '/^inherit private;$/{N;s/^inherit private;\n\( *\)\(.*\)$/\1inherit private;\n\1\2/}' "$FLAKE"

  info "Activating with the private overlay ..."
  activate
  trap - ERR
  info ""
  info "The private overlay is set up. Upgrades now update it together with the central repository."
}

remove() {
  has_overlay || die "This configuration has no private overlay."
  backup
  trap 'restore' ERR
  sed -i \
    -e '/^ *inputs\.private\.url = /d' \
    -e '/^ *inherit private;$/d' \
    -e 's|{ *central, *private, *\.\.\. *}:|{ central, ... }:|' \
    "$FLAKE"
  info "Activating without the private overlay ..."
  activate
  trap - ERR
  info ""
  info "The private overlay is removed."
}

main() {
  set -Eeuo pipefail
  local profile=""
  case "${1:-}" in
    setup)
      if [ $# -eq 4 ] && [ "$3" = --profile ]; then
        profile=$4
      else
        [ $# -eq 2 ] || usage
      fi
      ;;
    remove) [ $# -eq 1 ] || usage ;;
    *) usage ;;
  esac
  detect "$@"
  case "$1" in
    setup) setup "$2" "$profile" ;;
    remove) remove ;;
  esac
}

main "$@"
