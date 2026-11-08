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

# On a cable, tty1 often logs in while DHCP is still running. Keep checking
# for up to 30 s while NetworkManager is starting or bringing up a connection.
# Give up early once it has started and is neither connecting nor connected
# (e.g. "networking off" or "disconnected" on a machine without cable), so the
# Wi-Fi offer is not delayed there.
wait_for_network() {
  local i
  for i in $(seq 30); do
    online && return 0
    # STARTUP:STATE, e.g. "starting:connecting" or "started:networking off".
    case "$(nmcli -t -f STARTUP,STATE general 2>/dev/null)" in
    starting:* | *:connecting* | *:connected*) ;; # may still come up
    *) return 1 ;;
    esac
    [ "$i" -eq 2 ] && echo "Waiting for the network ..."
    sleep 1
  done
  return 1
}

hint() {
  printf '\nTo start the installer later, run: nixos-central-start\n'
}

printf '\nWelcome to the nixos-central installation image.\n\n'

until wait_for_network; do
  echo "No connection to github.com."
  if ask "Set up the network now (Wi-Fi: choose 'Activate a connection')?"; then
    nmtui || true
    echo "Checking the connection ..."
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
