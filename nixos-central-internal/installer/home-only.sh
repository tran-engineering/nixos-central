#!/usr/bin/env bash
# nixos-central home installer: sets up your user environment from the central
# repository on a Linux distribution other than NixOS. Runs as you and changes
# only your home directory, except for installing Nix and the GPU drivers, which
# it asks about first.
#
#   curl -sL https://tran-engineering.github.io/nixos-central/home-only.sh | sh
#   curl -sL https://tran-engineering.github.io/nixos-central/home-only.sh | sh -s -- --profile kt
#
# Everything below is a function definition; main runs on the very last line,
# so a truncated download does nothing.

if [ -z "${BASH_VERSION:-}" ]; then
  echo "nixos-central: this installer needs bash. Run it with: curl -sL https://tran-engineering.github.io/nixos-central/home-only.sh | bash" >&2
  exit 1
fi
set +o posix # /bin/sh may be bash in POSIX mode

init_globals() {
  # Override for testing, e.g. NIXOS_CENTRAL_FLAKE=git+https://github.com/tran-engineering/nixos-central?ref=my-branch
  CENTRAL="${NIXOS_CENTRAL_FLAKE:-git+https://github.com/tran-engineering/nixos-central}"
  PAGES=https://tran-engineering.github.io/nixos-central
  HM_DIR="$HOME/.config/home-manager" # must match services.home-manager.autoUpgrade.flakeDir
  NIX_DAEMON_PROFILE=/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  NVIDIA_VERSION_FILE=/proc/driver/nvidia/version

  PROFILE="" PROFILE_FLAG=0 INSTALL_NIX="" REPLACE_EXISTING="" GPU_SETUP=""
  USERNAME="" SYSTEM="" RELEASE="" PROFILES="" NVIDIA=null HM_BACKUP=""
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
Usage: curl -sL https://tran-engineering.github.io/nixos-central/home-only.sh | sh -s -- [options]

Sets up your user environment from nixos-central on this Linux machine (no NixOS
needed). Run it as yourself, not as root. Missing answers are asked for.

Options:
  --profile NAME       profile from the central repository (default: yours, else _default)
  --install-nix        install Nix if it is missing (needs sudo), without asking
  --replace-existing   move an existing ~/.config/home-manager aside, without asking
  --gpu-setup          set up GPU drivers for Nix programs (needs sudo once), without asking
  --no-gpu-setup       skip the GPU setup
  -h, --help           show this help
EOF
}

# Flakes are off by default; the user's nix.conf only gets them after the first switch.
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
      --profile)
        [ $# -ge 2 ] || {
          usage
          die "$flag needs a value."
        }
        value=$2
        shift
        ;;
    esac
    case "$flag" in
      --profile) PROFILE=$value PROFILE_FLAG=1 ;;
      --install-nix) INSTALL_NIX=yes ;;
      --replace-existing) REPLACE_EXISTING=yes ;;
      --gpu-setup) GPU_SETUP=yes ;;
      --no-gpu-setup) GPU_SETUP=no ;;
      *)
        usage
        die "Unknown option: $1"
        ;;
    esac
    shift
  done
}

require_tty() {
  if ! { [ -r /dev/tty ] && [ -w /dev/tty ]; }; then
    die "No terminal available for questions. Pass all answers as options (see --help)."
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

# confirm VAR "question" yes|no: sets VAR to yes or no, unless already set by a flag
confirm() {
  local __var=$1 __question=$2 __default=$3 __reply
  [ -n "${!__var}" ] && return
  if [ "$__default" = yes ]; then
    ask __reply "$__question [Y/n]"
  else
    ask __reply "$__question [y/N]"
  fi
  case "${__reply:-$__default}" in
    y | Y | yes | Yes) printf -v "$__var" yes ;;
    *) printf -v "$__var" no ;;
  esac
}

valid_profile() { [[ " $PROFILES " == *" $1 "* ]]; }

# ── checks ────────────────────────────────────────────────────────────────────

preflight() {
  heading "Checking this computer"
  if [ "$(id -u)" -eq 0 ]; then
    die "Run this installer as the user whose environment should be set up, not as root or with sudo. It asks for sudo itself where needed."
  fi
  [ "$(uname -s)" = Linux ] ||
    die "This installer supports Linux only (x86_64 and aarch64); this is $(uname -s)."
  case "$(uname -m)" in
    x86_64) SYSTEM=x86_64-linux ;;
    aarch64 | arm64) SYSTEM=aarch64-linux ;;
    *) die "Unsupported processor architecture $(uname -m); supported are x86_64 and aarch64 Linux." ;;
  esac
  if [ -e /etc/NIXOS ]; then
    die "This is NixOS. To install a new nixos-central machine, boot the NixOS installation image and run: curl -sL $PAGES | sh
On a machine already managed by nixos-central, update with: nixos-central-upgrade"
  fi

  USERNAME=$(id -un)
  [[ $USERNAME =~ ^[A-Za-z0-9._-]+$ ]] ||
    die "Unsupported login name '$USERNAME': only letters, digits, '.', '_' and '-' are supported."
  [ -d "$HOME" ] || die "Home directory '$HOME' does not exist."
  [[ $HOME =~ ^/[A-Za-z0-9._/-]+$ ]] ||
    die "Unsupported home directory '$HOME': only letters, digits, '.', '_', '-' and '/' are supported."

  curl -sfI --max-time 15 https://github.com >/dev/null ||
    die "No connection to github.com. Connect to the network first, then start the installer again."
  info "Linux $SYSTEM, user $USERNAME, network: OK"
}

# Ask before anything is changed, so declining leaves the machine untouched.
check_existing_home_flake() {
  [ -d "$HM_DIR" ] && [ -n "$(ls -A "$HM_DIR")" ] || return 0
  HM_BACKUP="$HM_DIR.backup-$(date +%Y%m%d-%H%M%S)"
  heading "Existing home-manager configuration"
  info "$HM_DIR already contains:"
  find "$HM_DIR" -mindepth 1 -maxdepth 1 -printf '    %f\n' >&2
  info "It will be moved to $HM_BACKUP (nothing is deleted)."
  confirm REPLACE_EXISTING "Move it and continue?" no
  [ "$REPLACE_EXISTING" = yes ] || die "Nothing was changed."
}

# ── nix ───────────────────────────────────────────────────────────────────────

load_nix_profile() {
  [ -r "$NIX_DAEMON_PROFILE" ] || return 0
  set +u
  # shellcheck disable=SC1090
  . "$NIX_DAEMON_PROFILE"
  set -u
}

ensure_nix() {
  heading "Nix"
  command -v nix >/dev/null || load_nix_profile # installed, but not in this shell's PATH
  if command -v nix >/dev/null; then
    info "Nix $(nix --version | awk '{print $NF}'): OK"
    return
  fi
  info "Nix is not installed. The official multi-user installer (https://nixos.org/download)"
  info "sets it up under /nix and needs root (sudo) for that, once."
  confirm INSTALL_NIX "Install Nix now?" no
  [ "$INSTALL_NIX" = yes ] || die "Nix is required. Nothing was changed."

  local script
  script=$(mktemp)
  curl -sSfL https://nixos.org/nix/install -o "$script" || die "Could not download the Nix installer."
  sh "$script" --daemon --yes </dev/null || die "Installing Nix failed."
  rm -f "$script"
  load_nix_profile
  command -v nix >/dev/null || die "Nix was installed but is not available; open a new terminal and run this installer again."
}

# ── profile ───────────────────────────────────────────────────────────────────

load_central() {
  info "Fetching nixos-central ($CENTRAL) ..."
  local facts
  facts=$(nixx eval --raw "$CENTRAL#lib" --apply 'l: l.release + " " + toString l.profileNames') ||
    die "Could not load $CENTRAL."
  RELEASE=${facts%% *}
  PROFILES=${facts#* }
}

choose_profile() {
  heading "Profile"
  local default=_default
  valid_profile "$USERNAME" && default=$USERNAME
  if [ "$PROFILE_FLAG" = 1 ]; then
    valid_profile "$PROFILE" || die "Unknown profile '$PROFILE'. Available: $PROFILES"
  else
    info "Profiles in the central repository: $PROFILES"
    while true; do
      ask PROFILE "Profile for $USERNAME" "$default"
      valid_profile "$PROFILE" && break
      info "Unknown profile '$PROFILE'. Choose one of: $PROFILES"
    done
  fi
  info "Using profile $PROFILE"
}

# ── gpu ───────────────────────────────────────────────────────────────────────

# Records the host's NVIDIA driver, if loaded; the Nix build must match it exactly.
detect_nvidia() {
  [ -r "$NVIDIA_VERSION_FILE" ] || return 0
  local version arch url hash
  version=$(head -n1 "$NVIDIA_VERSION_FILE" | grep -oE '[0-9]{3}\.[0-9]{2,3}(\.[0-9]{2,3})?' | head -n1)
  if [ -z "$version" ]; then
    info "An NVIDIA driver is loaded, but its version could not be read; continuing without it."
    return
  fi
  arch=x86_64
  [ "$SYSTEM" = aarch64-linux ] && arch=aarch64
  url="https://download.nvidia.com/XFree86/Linux-$arch/$version/NVIDIA-Linux-$arch-$version.run"
  info "NVIDIA driver $version found; fetching it for Nix programs (this may take a while) ..."
  if ! hash=$(nixx store prefetch-file --json "$url" | sed -n 's/.*"hash": *"\([^"]*\)".*/\1/p') || [ -z "$hash" ]; then
    info "Could not download $url; continuing without the NVIDIA driver."
    return
  fi
  NVIDIA="{ version = \"$version\"; sha256 = \"$hash\"; }"
  info "Using it means accepting NVIDIA's license: https://www.nvidia.com/content/DriverDownloads/licence.php"
}

ask_gpu_setup() {
  heading "GPU drivers"
  info "Graphical Nix programs need the GPU drivers set up once for the whole"
  info "machine (links under /run and /etc, via sudo)."
  confirm GPU_SETUP "Set up GPU drivers after installing?" yes
}

# ── install ───────────────────────────────────────────────────────────────────

sed_escape() { printf '%s' "$1" | sed 's/[\\|&]/\\&/g'; }

write_home_flake() {
  heading "Installing"
  if [ -n "$HM_BACKUP" ]; then
    mv "$HM_DIR" "$HM_BACKUP"
    info "Moved the previous configuration to $HM_BACKUP"
  fi
  mkdir -p "$HM_DIR"

  local template
  template=$(nixx eval --raw "$CENTRAL#templates.home.path")
  sed -e "s|@CENTRAL@|$(sed_escape "$CENTRAL")|g" \
    -e "s|@USER@|$USERNAME|g" \
    -e "s|@HOME@|$HOME|g" \
    -e "s|@SYSTEM@|$SYSTEM|g" \
    -e "s|@PROFILE@|$PROFILE|g" \
    -e "s|@PROFILES@|$PROFILES|g" \
    -e "s|@STATE_VERSION@|$RELEASE|g" \
    -e "s|@NVIDIA@|$(sed_escape "$NVIDIA")|g" \
    "$template/flake.nix" >"$HM_DIR/flake.nix"
  nixx flake lock "$HM_DIR"
  info "Wrote $HM_DIR/flake.nix"
}

# First switch, with the home-manager release the central repository pins.
# Files it would replace are kept with a .backup suffix.
activate_home() {
  info "Building and activating your environment (this may take a while) ..."
  nixx run "$CENTRAL#home-manager" -- switch --flake "$HM_DIR#$USERNAME" -b backup ||
    die "Activation failed; your current environment is still active. Fix the problem and run the installer again (with --replace-existing)."
}

gpu_setup_command() {
  local package
  package=$(nixx eval --raw "$HM_DIR#homeConfigurations.\"$USERNAME\".config.targets.genericLinux.gpu.setupPackage")
  printf 'sudo %s/bin/non-nixos-gpu-setup' "$package"
}

setup_gpu() {
  local command
  command=$(gpu_setup_command)
  if [ "$GPU_SETUP" != yes ]; then
    info "GPU setup skipped. To set it up later, run:  $command"
    return
  fi
  info "Setting up GPU drivers ..."
  # shellcheck disable=SC2086 # command is "sudo <store path>"
  $command || info "GPU setup failed. Graphical programs may not start; retry with:  $command"
}

# The login shell selected by the profile (nixos-central.shell), if it differs
# from the current one. Changing it needs root, so only print how.
shell_hint() {
  local shell path="" bin
  shell=$(nixx eval --raw "$HM_DIR#homeConfigurations.\"$USERNAME\".config.nixos-central.shell" 2>/dev/null) || return 0
  [ "$shell" = bash ] && return 0
  [ "$(basename "${SHELL:-}")" = "$shell" ] && return 0
  for bin in "$HOME/.nix-profile/bin" "$HOME/.local/state/nix/profile/bin"; do
    [ -x "$bin/$shell" ] && path="$bin/$shell" && break
  done
  [ -n "$path" ] || return 0
  info ""
  info "Your profile selects $shell as login shell. To switch to it:"
  info "    echo $path | sudo tee -a /etc/shells && chsh -s $path"
}

finish() {
  local kind="personal profile"
  [ "$PROFILE" = _default ] && kind="shared default profile"
  heading "Done"
  info "    user      $USERNAME ($HOME)"
  info "    profile   $PROFILE ($kind)"
  info "    config    $HM_DIR"
  info "    updates   daily, automatically (systemctl --user list-timers home-manager-auto-upgrade.timer)"
  info ""
  info "Update now:   nix flake update central --flake $HM_DIR && home-manager switch --flake $HM_DIR"
  info "Roll back:    home-manager generations, then run <generation>/activate"
  info "Changes to your environment belong in the profile in the central repository."
  shell_hint
  info ""
  info "Log out and back in to use everything from your profile."
}

main() {
  set -Eeuo pipefail
  init_globals
  parse_flags "$@"
  export NIX_CONFIG="experimental-features = nix-command flakes${NIX_CONFIG:+
$NIX_CONFIG}"
  preflight
  check_existing_home_flake
  ensure_nix
  load_central
  choose_profile
  ask_gpu_setup
  detect_nvidia
  write_home_flake
  activate_home
  setup_gpu
  finish
}

main "$@"
