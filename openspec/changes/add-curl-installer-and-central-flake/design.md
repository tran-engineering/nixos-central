# Design

## Context

Greenfield repository. The closest prior art is `KeeTraxx/k-nixos`, which installs from a dev machine via nixos-anywhere and commits each host (including `hardware-configuration.nix`) into the repo. That model needs repo write access and a second machine at install time; here the target installs itself from the live image and cannot commit back. So per-machine facts must live on the machine, while everything else stays central. Requirements are in `specs/` (installer, host-configuration, user-profiles, system-updates).

Live-image constraints: the NixOS ISO logs in as user `nixos` with passwordless sudo; `/nix/store` is a RAM-backed overlay; `sh` is bash; the script arrives on stdin.

## Goals / Non-Goals

**Goals:**
- One central flake is the single source of truth; machines carry only hostname, user, desktop, hardware.
- Installer works from a stock NixOS ISO (minimal or graphical) with no prior setup beyond network.
- Safe defaults: never wipe the wrong disk, never store secrets in the Nix store, updates never interrupt a running session.

**Non-Goals:**
- nixos-anywhere / remote installs, non-UEFI boot, TPM2 or unattended LUKS unlock, swap/hibernation tuning.
- Machine-local or user-local customization layers.
- Collision handling for identical usernames across different people.

## Decisions

### D1: Thin local flake in `/etc/nixos`, central repo as input
```
github:tran-engineering/nixos-central            /etc/nixos (per machine)
  flake.nix                                flake.nix  -> central.lib.mkHost {
    lib.mkHost                <-- input ---             hostname; user; desktop;
    modules/{base,desktops/*}                           modules = [ ./hardware-configuration.nix ]; }
    users/{_default,<name>}                flake.lock (pins central + transitive nixpkgs)
    install.sh                             hardware-configuration.nix
```
The local flake template lives in the central repo (`templates/host/flake.nix`) and is rendered by the installer via simple placeholder substitution. Machine facts are plain Nix string literals in that file, so changing the desktop later is a one-line edit.
- *Alternative: hosts committed to the central repo (k-nixos style).* Rejected: needs credentials on the target and a review step per install.
- *Alternative: generic flake reading `/etc/nixos/host.json` via `--impure`.* Rejected: impure evaluation everywhere, and `nixos-rebuild` without `--impure` would break.

### D2: `lib.mkHost` signature as the stable contract
`central.lib.mkHost { hostname, user, desktop, disk, stateVersion, modules ? [ ] }` returns a `nixosSystem`. `stateVersion` is written by the installer (`central.lib.release` at install time) so a later nixpkgs bump in the central repo never changes it. It wires disko's module (not used for mounts after install, see D4), home-manager as a NixOS module, base modules, the selected desktop module, and the user profile. This is the only surface machine flakes depend on; anything else is internal. Desktop validation: `assert` against `builtins.attrNames (builtins.readDir ./modules/desktops)` with a message listing valid names.

### D3: Profile resolution at evaluation time
`users/${user}` if `builtins.pathExists ./users/${user}` else `users/_default`. The chosen directory's `default.nix` is a home-manager module for `home-manager.users.${user}`. System-level account settings (normal user, `wheel`, `networkmanager`, `hashedPasswordFile`) are set by `mkHost`, not by profiles, so a personal profile cannot accidentally lock the user out. Profiles opt into the default with `imports = [ ../_default ];`.
- *Alternative: implicit merge of `_default` + personal.* Rejected (user decision): replace semantics are easier to reason about and allow dropping defaults.

### D4: Installer pipeline
```
main() {                      # called on the last line only -> truncated download is a no-op
  parse_flags; preflight      # UEFI (/sys/firmware/efi), NixOS ISO (/etc/NIXOS + iso label), GitHub reachable, sudo
  ask hostname/user/desktop   # read </dev/tty; desktops fetched from central repo listing
  pick_disk; confirm "yes"    # lsblk -J: TYPE=disk, size>=40G, !RM, TRAN!=usb, not parent of /iso mount
  ask luks passphrase x2; ask reuse-as-login-password / separate x2
  disko --mode destroy,format,mount  <central disk layout with --argstr device $DISK>
  nixos-generate-config --no-filesystems --root /mnt -> keep hardware-configuration.nix only
  render /mnt/etc/nixos/flake.nix from template; nix flake lock
  write /mnt/etc/secrets/<user>.hash (0400)  # mkpasswd -m sha-512
  nixos-install --root /mnt --flake /mnt/etc/nixos#$HOST --no-root-passwd
  summary; prompt reboot
}
```
- **Disk layout** is a central disko file parameterized by device: GPT, 1 GiB ESP (vfat, `/boot`), LUKS (`cryptroot`, `allowDiscards`) containing btrfs with subvolumes `@`, `@home`, `@nix` (zstd, noatime). Subvolumes make future snapshotting cheap at no cost now.
- **Filesystems after install**: `mkHost` imports the same disko layout so `fileSystems` and `boot.initrd.luks` derive from one definition (hence `nixos-generate-config --no-filesystems`). Disko mounts by GPT partition label (`disk-main-ESP`, `disk-main-luks`), so the runtime system does not depend on the device path. The local flake still records the disk as a stable `/dev/disk/by-id/...` path (an extra `mkHost` argument `disk`) for completeness and possible re-formatting.
- **Store on target disk**: `nixos-install --root /mnt` builds into `/mnt/nix/store`, avoiding RAM exhaustion on the ISO overlay. `disko-install` was rejected because it builds into the live store first.
- **LUKS passphrase** is written to a `mktemp` file on the ISO's tmpfs, passed to disko via `passwordFile`, and shredded on exit (trap). It never reaches `/mnt`.
- **User password**: hash written to `/etc/secrets/<user>.hash` on the target, consumed by `users.users.<user>.hashedPasswordFile`. No root password (`users.users.root.hashedPassword = "!"`), admin via sudo.
- **Running disko/nixos-generate-config**: via `nix run github:nix-community/disko/latest --` (pinned through the central flake: `nix run github:tran-engineering/nixos-central#disko`) so the installer depends only on Nix + network.
- **Logging**: `exec > >(tee -a /tmp/nixos-central-install.log) 2>&1` after prompts (prompts use `/dev/tty` directly, so secrets never hit the log).

### D5: GitHub Pages publishing
A GitHub Actions workflow on the default branch publishes the site with `index.html` being a copy of `install.sh` (served as `text/html`, which curl ignores). Using `-L` in the documented command covers the http→https and `/nixos-central`→`/nixos-central/` redirects.
- *Alternative: raw.githubusercontent.com URL.* Kept as a documented fallback; the Pages URL is shorter and stable.

### D6: Auto-upgrade
```
system.autoUpgrade = {
  enable = true; operation = "boot"; allowReboot = false;
  flake = "/etc/nixos"; flags = [ "--update-input" "central" ];
  dates = "daily"; persistent = true; randomizedDelaySec = "30min";
};
```
Semantics required: update only the `central` input (`nix flake update central --flake /etc/nixos`), write the lock file, then `nixos-rebuild boot --flake /etc/nixos`. `--update-input` is deprecated in newer Nix; if the stock module cannot express this on the pinned nixpkgs release, implement a small custom systemd service+timer with exactly these steps instead of `system.autoUpgrade`. Verified on nixos-26.05: nixos-rebuild-ng accepts `--update-input`, so the stock module is used (with `upgrade = false`, since there are no channels). Keeping the lock file updated in `/etc/nixos` (rather than `--no-write-lock-file`) means a manual `nixos-rebuild` reproduces what auto-upgrade built.

### D7: Reboot notification
A systemd **user** service + timer (every 30 min and at login) in the shared base compares `readlink /run/current-system` with `readlink /nix/var/nix/profiles/system`; if different and not yet notified for that target path (marker in `$XDG_RUNTIME_DIR`), it calls `notify-send`. `$XDG_RUNTIME_DIR` is per-session, matching "once per generation per session". Skipped when desktop is `none`.

### D8: `nixos-central-try`
Shell script package in the base: `sudo nixos-rebuild test --flake /etc/nixos#$(hostname) --override-input central github:tran-engineering/nixos-central/<branch> --no-write-lock-file`. `test` activates without a boot entry; `--no-write-lock-file` keeps `/etc/nixos/flake.lock` untouched.

### D9: nixpkgs pinning for ad-hoc shells
In `mkHost`: `nix.registry.nixpkgs.flake = nixpkgs;` and `nix.nixPath = [ "nixpkgs=${nixpkgs}" ];` (explicit, rather than relying on version-dependent `nixpkgs.flake.*` defaults), plus `nix.channel.enable = false`. Unfree is allowed system-wide (`nixpkgs.config.allowUnfree = true`); ad-hoc unfree still needs `NIXPKGS_ALLOW_UNFREE=1`, documented.

### D10: Pinned inputs
Central flake inputs: `nixpkgs` (current stable `nixos-YY.MM`), `home-manager` (matching release, follows nixpkgs), `disko` (follows nixpkgs). Machine flakes inherit these transitively through `central`, so a central `flake.lock` bump plus the machine's `central` bump moves everything together. A scheduled workflow (like k-nixos's `flake-update.yml`) bumps the central lock weekly.

## Risks / Trade-offs

- [Bad commit on main reaches every machine] → boot-mode upgrades + systemd-boot generations (keep ≥ 10 via `boot.loader.systemd-boot.configurationLimit`); CI runs `nix flake check` and builds a sample host for each desktop on PRs.
- [Wrong disk wiped] → strict auto-detect filters, explicit `yes` with model/size shown, `--disk` still confirmed.
- [`curl | sh` trust] → HTTPS-only documented URL, `main()` guard against truncation; document `curl -sLo install.sh …; less install.sh; sh install.sh` for the cautious.
- [Username collision across people in `users/`] → accepted for now (non-goal); a later change can add an explicit profile-name override.
- [`system.autoUpgrade` can't update a single input cleanly on the pinned release] → fallback custom service (D6).
- [Live ISO without Wi-Fi tooling configured] → preflight message pointing to `nmtui` (graphical ISO) / `nmcli` (minimal ISO).
- [GitHub outage/rate limits during daily upgrades] → `randomizedDelaySec`, `persistent`; failure leaves the current system untouched.

## Migration Plan

Greenfield; no migration. Rollout: (1) build central flake + `_default` profile, (2) test installer in a QEMU UEFI VM with a virtual NVMe and USB-attached ISO, (3) enable Pages, (4) install one real machine.

## Open Questions

- Which desktops ship in the first release besides `kde` and `none` (e.g. `gnome`, `niri`)? Adding one later is a new file under `modules/desktops/` and does not change the design.
- Contents of the `_default` profile (shell, editor, browser, git defaults).
