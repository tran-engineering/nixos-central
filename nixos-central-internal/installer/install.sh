#!/usr/bin/env bash
# nixos-central installer: installs a centrally managed NixOS from a booted
# NixOS live image.
#
#   curl -sL https://tran-engineering.github.io/nixos-central | sh
#   curl -sL https://tran-engineering.github.io/nixos-central | sh -s -- --hostname foo --user alice --desktop kde
#   ... | sh -s -- --private git+ssh://git@github.com/alice/private --profile developer
#
# Everything below is a function definition; main runs on the very last line,
# so a truncated download does nothing.

if [ -z "${BASH_VERSION:-}" ]; then
  echo "nixos-central: this installer needs bash. Run it with: curl -sL https://tran-engineering.github.io/nixos-central | bash" >&2
  exit 1
fi
set +o posix # /bin/sh on NixOS is bash in POSIX mode

init_globals() {
  # Override for testing, e.g. NIXOS_CENTRAL_FLAKE=git+https://github.com/tran-engineering/nixos-central?ref=my-branch
  CENTRAL="${NIXOS_CENTRAL_FLAKE:-git+https://github.com/tran-engineering/nixos-central}"
  LOG=/tmp/nixos-central-install.log
  WORK=/tmp/nixos-central/etc-nixos
  LUKS_KEY=/tmp/nixos-central-luks.key # must match nixos-central-internal/disko/default.nix
  SSH_DIR=/tmp/nixos-central-ssh # the primary user's new SSH key, until it is installed
  MIN_DISK_BYTES=$((40 * 1024 * 1024 * 1024))
  RESERVED_USERS=" root bin daemon nobody nogroup nixbld messagebus polkituser gdm flatpak sshd systemd-network
    systemd-resolve systemd-timesync systemd-oom systemd-coredump rtkit avahi geoclue pipewire
    nm-openvpn nm-iodine fwupd-refresh cups lp colord wheel users admin nixos "

  DEFAULT_TIME_ZONE=Europe/Zurich
  HOST="" USERNAME="" DESKTOP="" DISK="" KEYBOARD_LAYOUT="" TIME_ZONE=""
  PRIVATE_URL="" PROFILE=""
  NVIDIA=null NVIDIA_FLAG=0 NO_NVIDIA_FLAG=0
  HOST_FLAG=0 USER_FLAG=0 DESKTOP_FLAG=0 DISK_FLAG=0 KEYBOARD_LAYOUT_FLAG=0 TIME_ZONE_FLAG=0 PRIVATE_FLAG=0 PROFILE_FLAG=0
  DESKTOPS="" RELEASE="" DISK_ID="" PASSWORD_HASH="" KEYBOARD_LAYOUTS="" TIME_ZONES=""
  MENUS=0 GUM="" # gum menus for choices, or plain prompts (setup_menus)
  DEFAULT_PRIVATE="" PROFILES="" KEY_GENERATED=0 INSTALLED=0
  STEP="starting"
}

# ── output ────────────────────────────────────────────────────────────────────

info() { printf '%s\n' "$*" >&2; }
heading() { printf '\n\033[1m== %s ==\033[0m\n' "$*" >&2; }
die() {
  printf '\n\033[1;31mError:\033[0m %s\n' "$*" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
Usage: curl -sL https://tran-engineering.github.io/nixos-central | sh -s -- [options]

Installs NixOS managed by nixos-central on this machine. Missing values are asked for.

Options:
  --hostname NAME   machine name (lowercase letters, digits, dashes)
  --user NAME       login name of the primary user
  --desktop NAME    desktop environment (default: kde)
  --disk DEVICE     disk to erase and install on (default: first internal disk >= 40 GiB)
  --keyboard-layout NAME
                    keyboard layout (default: us): us, de, sg (Swiss German), sf (Swiss French)
  --time-zone NAME  time zone (default: Europe/Zurich); see: timedatectl list-timezones
  --private URL     set up this private overlay (README, "Private overlay"); generates
                    an SSH key for the user and shows it to add on GitHub
  --profile NAME    profile from the private overlay (needs --private;
                    default: the user's name if the overlay has it, else default)
  --nvidia          install the NVIDIA driver for the GPU found, without asking
  --no-nvidia       don't install the NVIDIA driver, and don't ask
  -h, --help        show this help

Choices are menus on the console. On a serial console, with TERM=dumb or with
NIXOS_CENTRAL_PLAIN=1 every question is a plain prompt instead.
EOF
}

nixx() { nix --extra-experimental-features "nix-command flakes" "$@"; }

# ── input ─────────────────────────────────────────────────────────────────────

parse_flags() {
  while [ $# -gt 0 ]; do
    local flag=$1 value=""
    case "$flag" in
      -h | --help)
        usage
        exit 0
        ;;
      --)
        shift
        continue
        ;;
      --*=*)
        value=${flag#*=}
        flag=${flag%%=*}
        ;;
      --hostname | --user | --desktop | --disk | --keyboard-layout | --time-zone | --private | --profile)
        [ $# -ge 2 ] || {
          usage
          die "$flag needs a value."
        }
        value=$2
        shift
        ;;
    esac
    case "$flag" in
      --hostname) HOST=$value HOST_FLAG=1 ;;
      --user) USERNAME=$value USER_FLAG=1 ;;
      --desktop) DESKTOP=$value DESKTOP_FLAG=1 ;;
      --disk) DISK=$value DISK_FLAG=1 ;;
      --keyboard-layout) KEYBOARD_LAYOUT=$value KEYBOARD_LAYOUT_FLAG=1 ;;
      --time-zone) TIME_ZONE=$value TIME_ZONE_FLAG=1 ;;
      --private) PRIVATE_URL=$value PRIVATE_FLAG=1 ;;
      --profile) PROFILE=$value PROFILE_FLAG=1 ;;
      --nvidia) NVIDIA_FLAG=1 ;;
      --no-nvidia) NO_NVIDIA_FLAG=1 ;;
      *)
        usage
        die "Unknown option: $1"
        ;;
    esac
    shift
  done
}

# Flag values are checked before anything else happens.
check_flags() {
  if [ "$HOST_FLAG" = 1 ] && ! valid_hostname "$HOST"; then
    die "Invalid hostname '$HOST': use 1-63 lowercase letters, digits and dashes, not starting or ending with a dash."
  fi
  if [ "$USER_FLAG" = 1 ] && ! valid_username "$USERNAME"; then
    die "Invalid or reserved username '$USERNAME': use lowercase letters, digits, '-' and '_', starting with a letter (max. 32)."
  fi
  if [ "$PRIVATE_FLAG" = 1 ] && [ -z "$PRIVATE_URL" ]; then
    die "--private needs the flake URL of the overlay, e.g. git+ssh://git@github.com/alice/private"
  fi
  if [ "$PROFILE_FLAG" = 1 ]; then
    [ "$PRIVATE_FLAG" = 1 ] ||
      die "--profile needs --private: a profile can only be chosen together with a private overlay."
    [[ $PROFILE =~ ^[A-Za-z0-9._-]+$ ]] || die "Invalid profile name '$PROFILE'."
  fi
  if [ "$NVIDIA_FLAG" = 1 ] && [ "$NO_NVIDIA_FLAG" = 1 ]; then
    die "--nvidia and --no-nvidia contradict each other: pass only one."
  fi
}

require_tty() {
  if ! { [ -r /dev/tty ] && [ -w /dev/tty ]; }; then
    die "No terminal available for questions. Pass all values as options (see --help)."
  fi
}

# ask VAR "question" [default]
ask() {
  local __var=$1 __question=$2 __default=${3:-} __reply
  require_tty
  if [ -n "$__default" ]; then
    read -r -p "$__question [$__default]: " __reply </dev/tty
    __reply=${__reply:-$__default}
  else
    read -r -p "$__question: " __reply </dev/tty
  fi
  printf -v "$__var" '%s' "$__reply"
}

# ask_secret VAR "question": hidden, entered twice, not empty
ask_secret() {
  local __var=$1 __question=$2 __first __second
  require_tty
  while true; do
    read -r -s -p "$__question: " __first </dev/tty
    echo >/dev/tty
    if [ -z "$__first" ]; then
      info "Must not be empty."
      continue
    fi
    read -r -s -p "Repeat to confirm: " __second </dev/tty
    echo >/dev/tty
    [ "$__first" = "$__second" ] && break
    info "The entries did not match, try again."
  done
  printf -v "$__var" '%s' "$__first"
}

# ── menus ─────────────────────────────────────────────────────────────────────
# Choices are gum menus when the terminal can show them, else plain prompts
# with the same texts and answers as without menus (serial consoles, the e2e
# test). Free text, secrets and the wipe confirmation always stay typed.

# Decides MENUS once, after ensure_root (globals don't survive the sudo re-exec).
setup_menus() {
  MENUS=0
  [ -z "${NIXOS_CENTRAL_PLAIN:-}" ] || return 0
  case "${TERM:-dumb}" in dumb | unknown) return 0 ;; esac
  # Opening it, not only its permissions: without a controlling terminal it fails.
  { : </dev/tty >/dev/tty; } 2>/dev/null || return 0
  if command -v gum >/dev/null; then
    GUM=$(command -v gum)
  else
    local out
    out=$(nixx build --no-link --print-out-paths --inputs-from "$CENTRAL" nixpkgs#gum 2>/dev/null | head -n1) || out=""
    if [ -z "$out" ] || [ ! -x "$out/bin/gum" ]; then
      info "Menus are not available (could not fetch gum); asking with plain prompts."
      return 0
    fi
    GUM=$out/bin/gum
  fi
  MENUS=1
}

# gum on the terminal itself: its screen goes to /dev/tty even when stderr is
# the install log, and only the answer comes back on stdout.
menu() { "$GUM" "$@" </dev/tty 2>/dev/tty; }

menu_cancelled() { die "Aborted. Nothing was changed."; }

# ask_until_valid VAR "question" default hint option...: plain prompt, repeated
# with the hint until the answer is one of the options.
ask_until_valid() {
  local __var=$1 __question=$2 __default=$3 __hint=$4
  shift 4
  local __options=" $* "
  while ask "$__var" "$__question" "$__default" && [[ $__options != *" ${!__var} "* ]]; do
    info "$__hint"
  done
}

# choose VAR "question" default intro option...: one of a few options, from a
# list with the default selected. Plain: the intro line (e.g. "Available
# desktops: ..."), then a prompt until the answer is one of the options.
choose() {
  local __var=$1 __question=$2 __default=$3 __intro=$4 __reply
  shift 4
  if [ "$MENUS" = 1 ]; then
    __reply=$(menu choose --header "$__question" --cursor "> " --selected "$__default" -- "$@") || menu_cancelled
    info "$__question: $__reply" # the menu disappears; keep the answer on screen
    printf -v "$__var" '%s' "$__reply"
  else
    [ -z "$__intro" ] || info "$__intro"
    ask_until_valid "$__var" "$__question" "$__default" "Choose one of: $*" "$@"
  fi
}

# choose_filtered VAR "question" default hint option...: one of many options,
# from a list filtered by typing, the default first. Plain: a prompt
# until the answer is one of the options, with the hint after a wrong one.
choose_filtered() {
  local __var=$1 __question=$2 __default=$3 __hint=$4 __reply
  shift 4
  if [ "$MENUS" = 1 ]; then
    # The default comes first, so Enter takes it before anything is typed.
    local __option __ordered=("$__default")
    for __option in "$@"; do [ "$__option" = "$__default" ] || __ordered+=("$__option"); done
    # Enter on a search without matches returns nothing: show the list again.
    __reply=""
    while [ -z "$__reply" ]; do
      __reply=$(menu filter --header "$__question (type to search)" --indicator ">" --placeholder "$__default" -- "${__ordered[@]}") || menu_cancelled
    done
    info "$__question: $__reply"
    printf -v "$__var" '%s' "$__reply"
  else
    ask_until_valid "$__var" "$__question" "$__default" "$__hint" "$@"
  fi
}

# confirm "question" yes|no [cancel]: true for yes. Plain: [Y/n] or [y/N] with
# the same answers as before menus. Escape answers no (gum can't tell them
# apart); Ctrl-C aborts the installer, or counts as no if "cancel" is given
# (questions after the install).
confirm() {
  local question=$1 default=$2 on_cancel=${3:-} answer status=0
  if [ "$MENUS" = 1 ]; then
    if [ "$default" = yes ]; then
      menu confirm --default=true "$question" >/dev/null || status=$?
    else
      menu confirm --default=false "$question" >/dev/null || status=$?
    fi
    case "$status" in
      0) return 0 ;;
      1) return 1 ;;
      *)
        [ "$on_cancel" = cancel ] && return 1
        menu_cancelled
        ;;
    esac
  fi
  if [ "$default" = yes ]; then
    ask answer "$question [Y/n]"
    case "$answer" in "" | y | Y | yes | Yes) return 0 ;; esac
  else
    ask answer "$question [y/N]"
    case "$answer" in y | Y | yes | Yes) return 0 ;; esac
  fi
  return 1
}

valid_hostname() { [[ $1 =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; }
valid_username() { [[ $1 =~ ^[a-z][a-z0-9_-]{0,31}$ ]] && [[ $RESERVED_USERS != *" $1 "* ]]; }
valid_desktop() { [[ " $DESKTOPS " == *" $1 "* ]]; }
valid_keyboard_layout() { [[ " $KEYBOARD_LAYOUTS " == *" $1 "* ]]; }
valid_time_zone() { [ -n "$1" ] && [[ " $TIME_ZONES " == *" $1 "* ]]; }

random_hostname() {
  local chars=abcdefghijklmnopqrstuvwxyz0123456789 suffix=""
  for _ in 1 2 3 4; do suffix+=${chars:RANDOM%${#chars}:1}; done
  printf 'nixos-%s' "$suffix"
}

# Ask for (or validate the flag value of) keyboard layout, time zone, hostname,
# user and desktop. The keyboard layout comes first and is switched to right away, so
# every following answer (including the disk passphrase) is typed with it.
collect_machine_facts() {
  heading "Machine"

  if [ "$KEYBOARD_LAYOUT_FLAG" = 1 ]; then
    valid_keyboard_layout "$KEYBOARD_LAYOUT" ||
      die "Unknown keyboard layout '$KEYBOARD_LAYOUT'. Available: $KEYBOARD_LAYOUTS"
  else
    # shellcheck disable=SC2086 # space-separated names
    choose KEYBOARD_LAYOUT "Keyboard layout" "us" "Available keyboard layouts: $KEYBOARD_LAYOUTS" $KEYBOARD_LAYOUTS
  fi
  apply_keyboard_layout

  if [ "$TIME_ZONE_FLAG" = 1 ]; then
    valid_time_zone "$TIME_ZONE" ||
      die "Unknown time zone '$TIME_ZONE'. See the valid names with: timedatectl list-timezones"
  else
    # shellcheck disable=SC2086 # space-separated names
    choose_filtered TIME_ZONE "Time zone" "$DEFAULT_TIME_ZONE" \
      "Unknown time zone. See the valid names with: timedatectl list-timezones" $TIME_ZONES
  fi

  if [ "$HOST_FLAG" = 0 ]; then
    local default
    default=$(random_hostname)
    while ask HOST "Hostname" "$default" && ! valid_hostname "$HOST"; do
      info "Use 1-63 lowercase letters, digits and dashes, not starting or ending with a dash."
    done
  fi

  if [ "$USER_FLAG" = 0 ]; then
    while ask USERNAME "Your username" && ! valid_username "$USERNAME"; do
      info "Use lowercase letters, digits, '-' and '_', starting with a letter (max. 32); system names like 'root' are reserved."
    done
  fi

  if [ "$DESKTOP_FLAG" = 1 ]; then
    valid_desktop "$DESKTOP" || die "Unknown desktop '$DESKTOP'. Available: $DESKTOPS"
  else
    # shellcheck disable=SC2086 # space-separated names
    choose DESKTOP "Desktop" "kde" "Available desktops: $DESKTOPS" $DESKTOPS
  fi

  collect_nvidia
}

# Records the nvidia fact of the machine flake (README, "NVIDIA graphics").
# Silent on a machine without an NVIDIA GPU.
collect_nvidia() {
  [ "$NO_NVIDIA_FLAG" = 0 ] || return 0

  local detected
  detected=$(bash "$(nixx eval --raw "$CENTRAL#lib.nvidiaDetect")") ||
    die "Could not check this computer for an NVIDIA GPU. To install without the NVIDIA driver, pass --no-nvidia."
  if [ "$detected" = null ]; then
    [ "$NVIDIA_FLAG" = 0 ] ||
      die "--nvidia was passed, but this computer has no NVIDIA GPU."
    return 0
  fi

  if [ "$NVIDIA_FLAG" = 0 ]; then
    heading "NVIDIA"
    local gpu
    gpu=$(lspci -d 10de: 2>/dev/null | grep -E 'VGA|3D|Display' || true)
    info "Found: ${gpu:-an NVIDIA GPU}"
    info "To be recorded in the machine's configuration: nvidia = $detected;"
    info "The driver uses NVIDIA's open kernel modules, which need a Turing or newer GPU"
    info "(RTX, GTX 16xx or newer)."
    confirm "Install the NVIDIA driver?" yes || return 0
  fi

  # Any HTTP response will do: this only checks that the server can be reached.
  curl -sI --max-time 15 https://download.nvidia.com/ >/dev/null ||
    die "No connection to download.nvidia.com, where the NVIDIA driver comes from. Check the network, or run the installer again with --no-nvidia to install without the driver."
  NVIDIA=$detected
}

# Switch this live console to the chosen layout: the console keymap from the
# central repository (loadkeys needs a real console, so this is a no-op e.g. in
# a terminal of the graphical live session).
apply_keyboard_layout() {
  local keymap
  keymap=$(nixx eval --raw "$CENTRAL#lib" --apply "l: l.keyboardLayouts.\"$KEYBOARD_LAYOUT\".consoleKeyMap") || return 0
  loadkeys "$keymap" >/dev/null 2>&1 || true
}

# ── checks ────────────────────────────────────────────────────────────────────

ensure_root() {
  [ "$(id -u)" -eq 0 ] && return
  command -v sudo >/dev/null || die "Please run this installer as root."
  # The script came through a pipe, so re-run its functions under sudo.
  exec sudo env NIXOS_CENTRAL_FLAKE="${NIXOS_CENTRAL_FLAKE:-}" NIXOS_CENTRAL_PLAIN="${NIXOS_CENTRAL_PLAIN:-}" TERM="${TERM:-dumb}" \
    bash -c "$(declare -f); main \"\$@\"" nixos-central-install "$@"
}

# Runs before asking for root, so other systems get no sudo prompt.
check_live_image() {
  if [ ! -e /etc/NIXOS ]; then
    die "This is not a NixOS installation image. To install nixos-central, boot its installation image
(https://github.com/tran-engineering/nixos-central/releases/latest/download/nixos-central-x86_64.iso).
To install only your user environment on this machine, run:

  curl -sL https://tran-engineering.github.io/nixos-central/home-only.sh | sh"
  fi
  if ! { command -v nixos-install && command -v nixos-generate-config; } >/dev/null; then
    die "This installer must run from a booted NixOS installation image, e.g. the nixos-central image:
https://github.com/tran-engineering/nixos-central/releases/latest/download/nixos-central-x86_64.iso"
  fi
  case "$(findmnt -no FSTYPE / 2>/dev/null)" in
    tmpfs | overlay | rootfs) ;;
    *) die "This does not look like the NixOS live image: the root filesystem is on a disk. Boot the USB image first." ;;
  esac
}

preflight() {
  heading "Checking this computer"
  [ -d /sys/firmware/efi ] ||
    die "The computer was started in legacy BIOS mode. Restart and boot the USB image in UEFI mode (check the firmware boot menu)."
  curl -sfI --max-time 15 https://github.com >/dev/null ||
    die "No connection to github.com. Connect to the network first (Wi-Fi: run 'nmtui'), then start the installer again."
  info "UEFI boot, live image and network: OK"

  info "Fetching nixos-central ($CENTRAL) ..."
  local facts
  facts=$(nixx eval --raw "$CENTRAL#lib" --apply 'l: builtins.concatStringsSep "\n" [ l.release (toString l.desktopNames) (toString l.keyboardLayoutNames) l.defaultPrivate ]') ||
    die "Could not load $CENTRAL."
  { read -r RELEASE; read -r DESKTOPS; read -r KEYBOARD_LAYOUTS; read -r DEFAULT_PRIVATE; } <<<"$facts"

  load_time_zones
  setup_menus
}

# Valid time zones: the live system's database, which the installed release's
# matches up to zones added in between.
load_time_zones() {
  TIME_ZONES=$(timedatectl list-timezones 2>/dev/null | tr '\n' ' ') || TIME_ZONES=""
  local dir
  for dir in /etc/zoneinfo /usr/share/zoneinfo; do
    [ -z "${TIME_ZONES// /}" ] && [ -d "$dir" ] || continue
    TIME_ZONES=$(cd "$dir" && find -L . -type f ! -path './posix/*' ! -path './right/*' |
      sed 's|^\./||' | grep -E '^[A-Z][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+)*$' | sort | tr '\n' ' ')
  done
  [ -n "${TIME_ZONES// /}" ] || die "Could not read the list of time zones of this live system."
}

# ── disk ──────────────────────────────────────────────────────────────────────

# Whole disk the live image was booted from, if any.
boot_disk() {
  local src parent
  src=$(findmnt -no SOURCE /iso 2>/dev/null) || return 0
  [ -n "$src" ] || return 0
  parent=$(lsblk -no PKNAME "$src" 2>/dev/null | head -n1)
  if [ -n "$parent" ]; then echo "/dev/$parent"; else echo "$src"; fi
}

list_disks() { lsblk -do PATH,SIZE,TYPE,TRAN,MODEL >&2; }

select_disk() {
  heading "Disk"
  if [ "$DISK_FLAG" = 1 ]; then
    if ! { [ -b "$DISK" ] && [ "$(lsblk -dno TYPE "$DISK")" = disk ]; }; then
      list_disks
      die "'$DISK' is not a disk."
    fi
    return
  fi

  local boot path size type rm ro tran
  boot=$(boot_disk)
  # Columns without a value (e.g. TRAN of virtio disks) must come last.
  while read -r path size type rm ro tran; do
    if [ "$type" != disk ] || [ "$rm" != 0 ] || [ "$ro" != 0 ]; then continue; fi
    [ "$tran" != usb ] || continue
    [ "$path" != "$boot" ] || continue
    [ "$size" -ge "$MIN_DISK_BYTES" ] || continue
    DISK=$path
    return
  done < <(lsblk -dbnr -o PATH,SIZE,TYPE,RM,RO,TRAN)

  info "Disks found:"
  list_disks
  die "No internal disk of at least 40 GiB found. Choose one explicitly with --disk /dev/..."
}

confirm_wipe() {
  local size model
  size=$(lsblk -dno SIZE "$DISK" | tr -d ' ')
  model=$(lsblk -dno MODEL "$DISK" | sed 's/ *$//')
  info "NixOS will be installed on:"
  info ""
  info "    $DISK ($size${model:+, $model})"
  info ""
  lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS "$DISK" >&2 || true
  info ""
  printf '\033[1;31mALL DATA ON %s WILL BE ERASED.\033[0m\n' "$DISK" >&2
  local answer
  ask answer "Type 'yes' to erase it and install"
  [ "$answer" = yes ] || die "Aborted. Nothing was changed."
}

# Stable /dev/disk/by-id name of $DISK, or $DISK itself.
stable_disk_path() {
  local link
  for link in /dev/disk/by-id/*; do
    case "$link" in *-part[0-9]* | */wwn-* | */nvme-eui.*) continue ;; esac
    [ "$(readlink -f "$link")" = "$DISK" ] && {
      echo "$link"
      return
    }
  done
  echo "$DISK"
}

# ── secrets ───────────────────────────────────────────────────────────────────

hash_password() {
  if command -v mkpasswd >/dev/null; then
    printf '%s' "$1" | mkpasswd --method=sha-512 --stdin
  elif command -v openssl >/dev/null; then
    printf '%s' "$1" | openssl passwd -6 -stdin
  else
    printf '%s' "$1" | nixx run nixpkgs#mkpasswd -- --method=sha-512 --stdin
  fi
}

collect_secrets() {
  heading "Disk encryption"
  info "The disk is encrypted. You will type this passphrase every time the computer starts."
  local luks password
  ask_secret luks "Disk passphrase"
  (
    umask 077
    printf '%s' "$luks" >"$LUKS_KEY"
  )

  heading "Login password"
  if confirm "Use the disk passphrase as login password for $USERNAME too?" yes; then
    password=$luks
  else
    ask_secret password "Login password for $USERNAME"
  fi
  PASSWORD_HASH=$(hash_password "$password")
  [ -n "$PASSWORD_HASH" ] || die "Could not hash the password."
}

# ── private overlay ───────────────────────────────────────────────────────────

# Runs `tool args...`, from the central repository's nixpkgs if the live image
# doesn't have it.
run_tool() {
  local tool=$1 package=$2
  shift 2
  if command -v "$tool" >/dev/null; then
    "$tool" "$@"
  else
    # Fetch quietly first, so download messages don't end up in the tool's output.
    nixx shell --inputs-from "$CENTRAL" "nixpkgs#$package" -c true 2>/dev/null || return 1
    nixx shell --inputs-from "$CENTRAL" "nixpkgs#$package" -c "$tool" "$@"
  fi
}

# The primary user's key: without passphrase, because the daily upgrade fetches
# the overlay with it unattended. A key from an earlier, failed attempt is
# reused, as it may already be on GitHub.
generate_ssh_key() {
  KEY_GENERATED=1
  if [ -s "$SSH_DIR/id_ed25519" ] && [ -s "$SSH_DIR/id_ed25519.pub" ]; then
    info "Using the SSH key from the previous attempt."
    return
  fi
  rm -rf "$SSH_DIR"
  (
    umask 077
    mkdir -p "$SSH_DIR"
  )
  run_tool ssh-keygen openssh -q -t ed25519 -N "" -C "$USERNAME@$HOST" -f "$SSH_DIR/id_ed25519" >/dev/null ||
    die "Could not generate an SSH key."
}

# Root in this live system fetches from GitHub with the new key and GitHub's
# known host key, as root on the installed system does (modules/base/private.nix).
configure_live_ssh() {
  local hostkey
  hostkey=$(nixx eval --raw "$CENTRAL#lib.githubHostKey") || die "Could not load GitHub's host key from $CENTRAL."
  printf 'github.com %s\n' "$hostkey" >"$SSH_DIR/known_hosts"
  install -d -m 0700 /root/.ssh
  cat >/root/.ssh/config <<EOF
# Written by the nixos-central installer (live system only).
Host github.com
  IdentityFile $SSH_DIR/id_ed25519
  IdentitiesOnly yes
  UserKnownHostsFile $SSH_DIR/known_hosts
  StrictHostKeyChecking yes
  BatchMode yes
EOF
}

show_public_key() {
  local pub
  pub=$(cat "$SSH_DIR/id_ed25519.pub")
  info ""
  info "Add this SSH key to your GitHub account (Settings -> SSH and GPG keys -> New SSH key,"
  info "https://github.com/settings/ssh/new). Scan the code to copy it on your phone:"
  info ""
  # Half blocks: two rows per line, so it fits an 80-column console.
  printf '%s' "$pub" | run_tool qrencode qrencode -t ansiutf8 -m 2 >&2 ||
    info "(The QR code could not be shown; copy the key below.)"
  info ""
  info "$pub"
  info ""
}

valid_profile() { [ -n "$1" ] && [[ " $PROFILES " == *" $1 "* ]]; }

# Can the key read the overlay, and which profiles does it have?
check_private_access() {
  info "Checking access to $PRIVATE_URL ..."
  local err
  if ! err=$(nixx flake metadata --refresh "$PRIVATE_URL" 2>&1 >/dev/null); then
    info "$err"
    info "Cannot read $PRIVATE_URL with the key above. Check the URL, and that the key is added to a GitHub account with access."
    return 1
  fi
  if ! PROFILES=$(nixx eval --raw "$PRIVATE_URL#homeModules" --apply 'm: toString (builtins.attrNames m)' 2>&1) || [ -z "$PROFILES" ]; then
    info "$PROFILES"
    info "$PRIVATE_URL is not a private overlay: it exports no homeModules (README, \"Private overlay\")."
    return 1
  fi
}

choose_profile() {
  local default=""
  if valid_profile "$USERNAME"; then
    default=$USERNAME
  elif valid_profile default; then
    default=default
  fi
  if [ "$PROFILE_FLAG" = 1 ]; then
    valid_profile "$PROFILE" || die "The overlay has no profile '$PROFILE'. Available: $PROFILES"
    return
  fi
  # shellcheck disable=SC2086 # space-separated names
  choose PROFILE "Profile" "$default" "Profiles in the overlay: $PROFILES" $PROFILES
}

# Optional: a private overlay, with a new SSH key for the primary user that is
# added to GitHub from a phone. Everything happens before the disk is touched.
collect_private() {
  heading "Private overlay"
  local answer
  if [ "$PRIVATE_FLAG" = 0 ]; then
    info "A private overlay adds your own setup from a private repository (README, \"Private overlay\")."
    confirm "Set up a private overlay?" no || return 0
    ask PRIVATE_URL "Overlay repository" "$DEFAULT_PRIVATE"
  fi

  generate_ssh_key
  configure_live_ssh
  show_public_key
  ask answer "Press Enter when the key is added on GitHub"
  while ! { check_private_access && choose_profile; }; do
    if [ "$MENUS" = 1 ]; then
      answer=$(menu choose --header "The overlay can't be read yet." --cursor "> " -- "Retry" "Skip the overlay") || menu_cancelled
      [ "$answer" = Retry ] || answer=s
    else
      ask answer "Retry, or skip the overlay? (r/s)" "r"
    fi
    case "$answer" in
      s | S | skip)
        PRIVATE_URL="" PROFILE=""
        info "Continuing without the private overlay. The key is installed anyway; add the overlay later with: nixos-central private setup"
        return 0
        ;;
    esac
  done
}

cleanup() {
  if [ -e "$LUKS_KEY" ]; then shred -u "$LUKS_KEY" 2>/dev/null || rm -f "$LUKS_KEY"; fi
  # After a failed install the key stays (tmpfs) for the next attempt.
  if [ "$INSTALLED" = 1 ] && [ -e "$SSH_DIR" ]; then
    shred -u "$SSH_DIR"/* 2>/dev/null || true
    rm -rf "$SSH_DIR"
  fi
}

# ── install ───────────────────────────────────────────────────────────────────

on_error() {
  printf '\n\033[1;31mInstallation failed during: %s\033[0m\n' "$STEP" >&2
  printf 'Full log: %s\n' "$LOG" >&2
  printf 'Nothing will be rebooted. Fix the problem and run the installer again.\n' >&2
}

sed_escape() { printf '%s' "$1" | sed 's/[\\|&]/\\&/g'; }

write_machine_flake() {
  rm -rf "$WORK"
  mkdir -p "$WORK"
  nixos-generate-config --no-filesystems --show-hardware-config >"$WORK/hardware-configuration.nix"

  local template
  template=$(nixx eval --raw "$CENTRAL#templates.host.path")
  sed -e "s|@CENTRAL@|$(sed_escape "$CENTRAL")|g" \
    -e "s|@HOSTNAME@|$HOST|g" \
    -e "s|@USER@|$USERNAME|g" \
    -e "s|@DESKTOP@|$DESKTOP|g" \
    -e "s|@DESKTOPS@|$DESKTOPS|g" \
    -e "s|@DISK@|$(sed_escape "$DISK_ID")|g" \
    -e "s|@KEYBOARD_LAYOUT@|$KEYBOARD_LAYOUT|g" \
    -e "s|@KEYBOARD_LAYOUTS@|$KEYBOARD_LAYOUTS|g" \
    -e "s|@TIME_ZONE@|$(sed_escape "$TIME_ZONE")|g" \
    -e "s|@STATE_VERSION@|$RELEASE|g" \
    -e "s|@NVIDIA@|$(sed_escape "$NVIDIA")|g" \
    "$template/flake.nix" >"$WORK/flake.nix"
  if [ -n "$PRIVATE_URL" ]; then
    # The same edit as `nixos-central private setup`, so `remove` undoes it.
    # shellcheck disable=SC1090
    source "$(nixx eval --raw "$CENTRAL#lib.privateFlakeEdit")"
    flake_add_overlay "$WORK/flake.nix" nixos "$PRIVATE_URL" "$PROFILE"
  fi
  nixx flake lock "path:$WORK"
}

install_system() {
  heading "Installing"
  info "Log: $LOG"
  exec > >(tee -a "$LOG") 2>&1
  trap on_error ERR

  STEP="writing the machine configuration"
  info "==> $STEP"
  DISK_ID=$(stable_disk_path)
  write_machine_flake

  STEP="partitioning and encrypting $DISK"
  info "==> $STEP"
  nixx run "$CENTRAL#disko" -- --mode destroy,format,mount --yes-wipe-all-disks --flake "path:$WORK#$HOST"

  STEP="copying the configuration to the new system"
  info "==> $STEP"
  mkdir -p /mnt/etc/nixos
  cp -R "$WORK/." /mnt/etc/nixos/
  install -d -m 0700 /mnt/etc/secrets
  (
    umask 077
    printf '%s\n' "$PASSWORD_HASH" >"/mnt/etc/secrets/$USERNAME.hash"
  )
  chmod 0400 "/mnt/etc/secrets/$USERNAME.hash"

  STEP="installing NixOS (this takes a while)"
  info "==> $STEP"
  nixos-install --root /mnt --flake "/mnt/etc/nixos#$HOST" --no-root-passwd --no-channel-copy

  if [ "$KEY_GENERATED" = 1 ]; then
    STEP="installing the SSH key for $USERNAME"
    info "==> $STEP"
    local ssh="/mnt/home/$USERNAME/.ssh"
    install -d -m 0700 "$ssh"
    install -m 0600 "$SSH_DIR/id_ed25519" "$ssh/id_ed25519"
    install -m 0644 "$SSH_DIR/id_ed25519.pub" "$ssh/id_ed25519.pub"
    # The user exists once nixos-enter has run the new system's activation.
    nixos-enter --root /mnt -c "chown $USERNAME:users /home/$USERNAME && chown -R $USERNAME:users /home/$USERNAME/.ssh"
  fi

  trap - ERR
  INSTALLED=1
  STEP="done"
}

finish() {
  heading "Done"
  info "NixOS is installed:"
  info "    hostname  $HOST"
  info "    user      $USERNAME"
  info "    desktop   $DESKTOP"
  info "    keyboard  $KEYBOARD_LAYOUT"
  info "    time zone $TIME_ZONE"
  info "    disk      $DISK_ID"
  case "$NVIDIA" in
    null) ;;
    *BusId*) info "    NVIDIA    driver with PRIME offload (nvidia-offload <program>)" ;;
    *) info "    NVIDIA    driver" ;;
  esac
  if [ -n "$PRIVATE_URL" ]; then
    info "    overlay   $PRIVATE_URL"
    info "    profile   $PROFILE"
  fi
  if [ "$KEY_GENERATED" = 1 ]; then
    info "    SSH key   /home/$USERNAME/.ssh/id_ed25519"
  fi
  info ""
  info "Remove the USB stick when the computer restarts."
  if confirm "Reboot now?" yes cancel; then
    systemctl reboot
  else
    info "Not rebooting. The new system is still mounted at /mnt."
  fi
}

main() {
  set -Eeuo pipefail
  init_globals
  parse_flags "$@"
  check_flags
  check_live_image
  ensure_root "$@"
  trap cleanup EXIT
  preflight
  collect_machine_facts
  select_disk
  confirm_wipe
  collect_secrets
  collect_private
  install_system
  finish
}

main "$@"
