# nixos-central-start: offered on the first console of the installation image
# (nixos-central-internal/iso). Gets the machine online if needed, then runs the
# installer from the central repository's default branch, so an image of any
# age installs with the current installer.
#
# Override for testing, e.g. NIXOS_CENTRAL_FLAKE=git+https://github.com/tran-engineering/nixos-central?ref=my-branch

CENTRAL="${NIXOS_CENTRAL_FLAKE:-git+https://github.com/tran-engineering/nixos-central}"

# ask "question": true for yes (the default), false for anything else.
ask() {
  local reply
  read -r -p "$1 [Y/n]: " reply || return 1
  case "$reply" in
  "" | [yY] | [yY][eE][sS]) return 0 ;;
  *) return 1 ;;
  esac
}

online() { curl -sfI --max-time 10 https://github.com >/dev/null; }

hint() {
  printf '\nTo start the installer later, run: nixos-central-start\n'
}

printf '\nWelcome to the nixos-central installation image.\n\n'

until online; do
  echo "No connection to github.com."
  if ask "Set up the network now (Wi-Fi: choose 'Activate a connection')?"; then
    nmtui || true
  else
    hint
    exit 0
  fi
done

if ! ask "Install nixos-central on this computer?"; then
  hint
  exit 0
fi

# --refresh: a second attempt gets the newest default branch, not a cached one.
if ! nix run --refresh "$CENTRAL#installer"; then
  hint
  exit 1
fi
