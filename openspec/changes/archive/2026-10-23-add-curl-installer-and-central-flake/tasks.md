# Tasks

Scope assumption: first release ships desktops `kde` and `none`; further desktops are follow-up changes (design.md, Open Questions). The `_default` profile starts minimal (shell, git, editor, browser) and is refined later.

## 1. Repository scaffolding

- [x] 1.1 Initialize git repo with `flake.nix` declaring inputs `nixpkgs` (current stable), `home-manager` (matching release, follows nixpkgs), `disko` (follows nixpkgs); verify `nix flake lock` succeeds and `flake.lock` lists all three
- [x] 1.2 Create directory layout `lib/`, `modules/base/`, `modules/desktops/`, `users/_default/`, `templates/host/`, `disko/`, `installer/`; verify `nix flake show` evaluates
- [x] 1.3 Add `README.md` skeleton with the one-line install command (`curl -sL … | sh -s -- …`) and the cautious download-then-run variant; verify the commands in the README match the flag names in the installer spec

## 2. Central host builder and base configuration

- [x] 2.1 Add `disko/default.nix` layout (GPT, 1 GiB ESP, LUKS `cryptroot` with allowDiscards, btrfs subvolumes `@`, `@home`, `@nix`, zstd/noatime) parameterized by device; verify `nix eval` of the layout with a sample device succeeds
- [x] 2.2 Implement `lib.mkHost { hostname, user, desktop, disk, modules ? [] }` wiring disko module + layout, home-manager NixOS module, base modules, desktop module, user profile; expose as `lib.mkHost` in `flake.nix`; verify a sample `nixosConfigurations.ci-kde` built via `mkHost` evaluates with `nix flake check --no-build`
- [x] 2.3 Add `modules/base`: systemd-boot (`configurationLimit = 10`), NetworkManager, flakes + nix-command, hostname, `allowUnfree`, root login disabled (`hashedPassword = "!"`); verify by inspecting `nix eval` of the corresponding options on `ci-kde`
- [x] 2.4 Pin ad-hoc shells: `nix.registry.nixpkgs.flake`, `nix.nixPath = [ "nixpkgs=${nixpkgs}" ]`, `nix.channel.enable = false`; verify in a VM (`nixos-rebuild build-vm`) that `nix-shell -p hello` and `nix shell nixpkgs#hello` work and `nix flake metadata nixpkgs` shows the system's revision
- [x] 2.5 Add `modules/desktops/kde.nix` (Plasma 6 + SDDM) and `modules/desktops/none.nix`; add assertion in `mkHost` that rejects unknown desktops listing valid names; verify `ci-kde` and `ci-none` evaluate and a config with `desktop = "foo"` fails with the list of names
- [x] 2.6 Expose installer helpers as flake apps/packages (`disko` pinned via inputs); verify `nix run .#disko -- --help` works
- [x] 2.7 Document `lib.mkHost` arguments and the available desktops in `README.md`; verify the example in the README evaluates

## 3. User profiles

- [x] 3.1 In `mkHost`, create primary user (normal, `wheel`, `networkmanager`, `hashedPasswordFile = /etc/secrets/<user>.hash`, mutableUsers false); verify via `nix eval` on `ci-kde`
- [x] 3.2 Implement evaluation-time profile resolution (`users/<user>` if `pathExists`, else `users/_default`) into `home-manager.users.<user>`; verify `ci-kde` with user `nobodyhere` uses `_default` and a test profile `users/ci-user` (importing `../_default`) is picked for user `ci-user`
- [x] 3.3 Write minimal `users/_default/default.nix` home-manager module (shell, git, editor, browser, `home.stateVersion`); verify `ci-kde` builds (`nix build .#nixosConfigurations.ci-kde.config.system.build.toplevel`)
- [x] 3.4 Document in `README.md` how to add a personal profile via PR, replace-vs-import-default semantics, and `nix-shell -p` for experiments; verify the documented profile example evaluates

## 4. Updates and experimentation

- [x] 4.1 Add auto-upgrade to base: daily, persistent, `randomizedDelaySec = "30min"`, `operation = "boot"`, `allowReboot = false`, updating only `central` in `/etc/nixos`; if stock `system.autoUpgrade` cannot express single-input update on the pinned release, implement an equivalent systemd service+timer; verify in a VM that running the unit updates `central` in `flake.lock`, adds a boot entry, and leaves `/run/current-system` unchanged
- [x] 4.2 Add reboot-pending notifier (systemd user service + timer every 30 min and at login, marker in `$XDG_RUNTIME_DIR`, disabled for `none`); verify in a KDE VM that after a staged generation a single notification appears and none after reboot
- [x] 4.3 Add `nixos-central-try <branch>` script package (`nixos-rebuild test --override-input central github:tran-engineering/nixos-central/<branch> --no-write-lock-file`, error on missing branch); verify in a VM that `flake.lock` is unchanged, no boot entry is added, and a nonexistent branch exits non-zero
- [x] 4.4 Document update behaviour, rollback via boot menu, and `nixos-central-try` in `README.md`; verify commands as written

## 5. Installer script

- [x] 5.1 Create `installer/install.sh` with `main()` invoked only on the last line, strict mode, flag parsing (`--hostname --user --desktop --disk`, usage on unknown flags); verify with `shellcheck` and that a truncated copy (`head -c 50%`) piped to `sh` does nothing
- [x] 5.2 Implement preflight (re-exec via sudo, NixOS live image, UEFI via `/sys/firmware/efi`, GitHub reachable) with actionable messages; verify each failure path in a QEMU VM (BIOS boot, network off)
- [x] 5.3 Implement `/dev/tty` prompts with defaults (hostname `nixos-XXXX`, desktop `kde`) and validation (RFC 1123 hostname, POSIX lowercase username, not reserved, desktop in central list); verify interactively and with flags, including invalid inputs
- [x] 5.4 Implement disk auto-selection (whole disk ≥ 40 GiB, not removable, not USB, not the ISO's backing device) and typed `yes` confirmation showing path/size/model; verify in QEMU with ISO attached as USB first and an NVMe disk second, and with only a 32 GiB disk (abort + list)
- [x] 5.5 Implement LUKS passphrase prompt (hidden, twice, non-empty), reuse-as-login-password offer or separate password prompt, hashing with `mkpasswd -m sha-512`; temp files on tmpfs with shred-on-exit trap; verify no passphrase or hash appears in `/nix/store` (`grep -r`) or the install log
- [x] 5.6 Implement install steps: disko destroy/format/mount with by-id device, `nixos-generate-config --no-filesystems --root /mnt`, render `templates/host/flake.nix` into `/mnt/etc/nixos`, `nix flake lock`, write `/mnt/etc/secrets/<user>.hash` (0400), `nixos-install --root /mnt --flake /mnt/etc/nixos#<host> --no-root-passwd`; log to `/tmp/nixos-central-install.log`, report failing step; verify end-to-end in QEMU UEFI VM
- [x] 5.7 Implement summary and reboot prompt; verify after reboot in VM: LUKS prompt, login with chosen password, `sudo` works, hostname and desktop correct, `/etc/nixos` contains only flake, lock, hardware config
- [x] 5.8 Document installer flags, prompts, disk selection rules and Wi-Fi prerequisites (`nmtui`/`nmcli`) in `README.md`; verify against the implemented behaviour

## 6. Publishing and CI

- [x] 6.1 Add GitHub Actions workflow publishing `installer/install.sh` as `index.html` to GitHub Pages on the default branch; verify `curl -sL https://tran-engineering.github.io/nixos-central | head` returns the script and `http://` also works with `-L`
- [x] 6.2 Add CI on PRs: `nix flake check`, `shellcheck installer/install.sh`, build `ci-kde` and `ci-none` toplevels; verify a PR run passes
- [ ] 6.3 Add scheduled workflow bumping the central `flake.lock` weekly via PR; verify it opens a PR on manual dispatch

## 7. Integration

- [ ] 7.1 Full flow in QEMU from stock NixOS ISO using the published URL with no flags: install, reboot, then merge a profile `users/<user>` on a branch, run `nixos-central-try <branch>`, reboot (reverts), merge, trigger auto-upgrade, receive notification, reboot into new profile; verify each spec scenario observed
- [x] 7.2 Install one real machine via the published URL; verify boot, login, Wi-Fi, and first auto-upgrade

## Workflow follow-up

- Archive the change after review once all tasks are complete.
