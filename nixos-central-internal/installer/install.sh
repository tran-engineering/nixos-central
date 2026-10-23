#!/usr/bin/env bash
# nixos-central installer: installs a centrally managed NixOS from a booted
# NixOS live image.
#
#   curl -sL https://tran-engineering.github.io/nixos-central | sh
#   curl -sL https://tran-engineering.github.io/nixos-central | sh -s -- --hostname foo --user alice --desktop kde
#
# Everything below is a function definition; main runs on the very last line,
# so a truncated download does nothing.

if [ -z "${BASH_VERSION:-}" ]; then
  echo "nixos-central: this installer needs bash. Run it with: curl -sL https://tran-engineering.github.io/nixos-central | bash" >&2
  exit 1
fi
set +o posix # /bin/sh on NixOS is bash in POSIX mode

init_globals() {
  # Override for testing, e.g. NIXOS_CENTRAL_FLAKE=github:tran-engineering/nixos-central/my-branch
  CENTRAL="${NIXOS_CENTRAL_FLAKE:-github:tran-engineering/nixos-central}"
  LOG=/tmp/nixos-central-install.log
  WORK=/tmp/nixos-central/etc-nixos
  LUKS_KEY=/tmp/nixos-central-luks.key # must match nixos-central-internal/disko/default.nix
  MIN_DISK_BYTES=$((40 * 1024 * 1024 * 1024))
  RESERVED_USERS=" root bin daemon nobody nogroup nixbld messagebus polkituser sddm sshd systemd-network
    systemd-resolve systemd-timesync systemd-oom systemd-coredump rtkit avahi geoclue pipewire
    nm-openvpn nm-iodine fwupd-refresh cups lp colord wheel users admin nixos "

  HOST="" USERNAME="" DESKTOP="" DISK=""
  HOST_FLAG=0 USER_FLAG=0 DESKTOP_FLAG=0 DISK_FLAG=0
  DESKTOPS="" RELEASE="" DISK_ID="" PASSWORD_HASH=""
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
  -h, --help        show this help
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
      --hostname | --user | --desktop | --disk)
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

valid_hostname() { [[ $1 =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; }
valid_username() { [[ $1 =~ ^[a-z][a-z0-9_-]{0,31}$ ]] && [[ $RESERVED_USERS != *" $1 "* ]]; }
valid_desktop() { [[ " $DESKTOPS " == *" $1 "* ]]; }

random_hostname() {
  local chars=abcdefghijklmnopqrstuvwxyz0123456789 suffix=""
  for _ in 1 2 3 4; do suffix+=${chars:RANDOM%${#chars}:1}; done
  printf 'nixos-%s' "$suffix"
}

# Ask for (or validate the flag value of) hostname, user and desktop.
collect_machine_facts() {
  heading "Machine"

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
    info "Available desktops: $DESKTOPS"
    while ask DESKTOP "Desktop" "kde" && ! valid_desktop "$DESKTOP"; do
      info "Choose one of: $DESKTOPS"
    done
  fi
}

# ── checks ────────────────────────────────────────────────────────────────────

ensure_root() {
  [ "$(id -u)" -eq 0 ] && return
  command -v sudo >/dev/null || die "Please run this installer as root."
  # The script came through a pipe, so re-run its functions under sudo.
  exec sudo env NIXOS_CENTRAL_FLAKE="${NIXOS_CENTRAL_FLAKE:-}" \
    bash -c "$(declare -f); main \"\$@\"" nixos-central-install "$@"
}

preflight() {
  heading "Checking this computer"
  if ! { [ -e /etc/NIXOS ] && command -v nixos-install && command -v nixos-generate-config; } >/dev/null; then
    die "This installer must run from a booted NixOS installation image (https://nixos.org/download)."
  fi
  case "$(findmnt -no FSTYPE / 2>/dev/null)" in
    tmpfs | overlay | rootfs) ;;
    *) die "This does not look like the NixOS live image: the root filesystem is on a disk. Boot the USB image first." ;;
  esac
  [ -d /sys/firmware/efi ] ||
    die "The computer was started in legacy BIOS mode. Restart and boot the USB image in UEFI mode (check the firmware boot menu)."
  curl -sfI --max-time 15 https://github.com >/dev/null ||
    die "No connection to github.com. Connect to the network first (Wi-Fi: run 'nmtui'), then start the installer again."
  info "UEFI boot, live image and network: OK"

  info "Fetching nixos-central ($CENTRAL) ..."
  local facts
  facts=$(nixx eval --raw "$CENTRAL#lib" --apply 'l: l.release + " " + toString l.desktopNames') ||
    die "Could not load $CENTRAL."
  RELEASE=${facts%% *}
  DESKTOPS=${facts#* }
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
  local luks password answer
  ask_secret luks "Disk passphrase"
  (
    umask 077
    printf '%s' "$luks" >"$LUKS_KEY"
  )

  heading "Login password"
  ask answer "Use the disk passphrase as login password for $USERNAME too? [Y/n]"
  case "$answer" in
    "" | y | Y | yes | Yes) password=$luks ;;
    *) ask_secret password "Login password for $USERNAME" ;;
  esac
  PASSWORD_HASH=$(hash_password "$password")
  [ -n "$PASSWORD_HASH" ] || die "Could not hash the password."
}

cleanup() {
  if [ -e "$LUKS_KEY" ]; then shred -u "$LUKS_KEY" 2>/dev/null || rm -f "$LUKS_KEY"; fi
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
    -e "s|@STATE_VERSION@|$RELEASE|g" \
    "$template/flake.nix" >"$WORK/flake.nix"
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

  trap - ERR
  STEP="done"
}

finish() {
  heading "Done"
  info "NixOS is installed:"
  info "    hostname  $HOST"
  info "    user      $USERNAME"
  info "    desktop   $DESKTOP"
  info "    disk      $DISK_ID"
  info ""
  info "Remove the USB stick when the computer restarts."
  local answer
  ask answer "Reboot now? [Y/n]"
  case "$answer" in
    "" | y | Y | yes | Yes) systemctl reboot ;;
    *) info "Not rebooting. The new system is still mounted at /mnt." ;;
  esac
}

main() {
  set -Eeuo pipefail
  init_globals
  parse_flags "$@"
  check_flags
  ensure_root "$@"
  trap cleanup EXIT
  preflight
  collect_machine_facts
  select_disk
  confirm_wipe
  collect_secrets
  install_system
  finish
}

main "$@"
