# Tasks

## 1. Shared U2F settings and package

- [x] 1.1 Create `modules/base/u2f.nix` and import it from `modules/base/default.nix`. Under `lib.mkIf (desktop != "none")`, set `security.pam.u2f.settings` (`origin`/`appid` = `pam://nixos-central`, `cue = true`) and add `pkgs.pam_u2f` to `environment.systemPackages`. Leave `security.pam.u2f.enable` unset (design D2). Verify that `nix build .#checks.x86_64-linux.host-ci-kde` and `host-ci-none` still build.
- [x] 1.2 Add an evaluation check `u2f-pam` to `nixos-central-internal/tests/default.nix`. For hosts with each of the four desktops, assert that `environment.etc."pam.d/login".text`, `pam.d/sudo` and `pam.d/su` do not contain `pam_u2f`. On the `none` host, assert that no `pam.d/*` entry contains `pam_u2f` and that `pamu2fcfg` is not in the system path. Verify with `nix build .#checks.x86_64-linux.u2f-pam`.

## 2. Display-manager login (SDDM, GDM)

- [x] 2.1 In `u2f.nix`, add the hand-written `u2f` auth rule (`sufficient`, pam_u2f module path, shared settings, order = `rules.auth.login.order - 10`). Add it to `sddm` or `gdm-password`, whichever display manager is enabled on a graphical machine (design D3). Verify by extending `u2f-pam`: for kde and niri-noctalia, `pam.d/sddm` contains `pam_u2f.so` with `origin=pam://nixos-central` on a line before the `substack login` line. For gnome, `pam.d/gdm-password` does the same, and also for a kde machine switched to GDM (whose `pam.d/sddm` then has no pam_u2f). The check passes.

## 3. Lock screens (KDE, GNOME, Noctalia)

- [x] 3.1 In `u2f.nix`, set `security.pam.services.kde.u2f.enable = true` when the desktop is kde (design D4). Verify by extending `u2f-pam`: `pam.d/kde` contains `pam_u2f.so` before `pam_unix.so` in the auth section. On gnome and niri-noctalia hosts, `pam.d/kde` does not contain `pam_u2f`. The check passes.
- [x] 3.2 In `u2f.nix`, when the desktop is niri-noctalia, define `security.pam.services.noctalia` with `u2f.enable = true` and set `systemd.user.services.noctalia-shell.environment.NOCTALIA_PAM_SERVICE = "noctalia"`. Add a comment that Noctalia falls back to `login` without this variable (design D5). Verify by extending `u2f-pam`: `pam.d/noctalia` contains `pam_u2f.so` before `pam_unix.so`, and the user service environment has the variable. The check passes. GNOME's lock screen is covered by `gdm-password` from 2.1, so it needs no separate task.

## 4. Documentation

- [ ] 4.1 Add a README section "Signing in with a security key (YubiKey)", placed after "How a machine is configured" / "Desktops". It covers:
  - the enrollment command `mkdir -p ~/.config/Yubico && pamu2fcfg -o pam://nixos-central -i pam://nixos-central > ~/.config/Yubico/u2f_keys`
  - adding a backup key with `-n` and `>>`
  - copying the file to the user's other machines
  - removing a lost key
  - per desktop, where the key works and how to trigger it (empty field + Enter on SDDM and the KDE lock screen)
  - that TTY login and `sudo` stay password-only
  - the security note that whoever holds the key can unlock the session

  Verify by running the documented enrollment command on a machine built from this branch. It must produce a `u2f_keys` line containing `pam://nixos-central`-bound credentials, and that line must be accepted in 5.1.

## 5. Integration verification on hardware

- [ ] 5.1 On a real machine (or a VM with USB passthrough of a YubiKey), one per desktop (kde, gnome, niri-noctalia), enroll a key as the README describes. Then check:
  - login and unlock work with a key touch
  - login and unlock work with the password, both with the key plugged in and unplugged, with no noticeable delay when it is unplugged
  - `sudo` and TTY login do not prompt for the key

  Record the actual prompt behavior per desktop and correct the README in 4.1 if it differs.
- [ ] 5.2 Copy the enrolled `~/.config/Yubico/u2f_keys` to a second nixos-central machine and verify that the key is accepted there without re-enrolling (spec: portable enrollment).
- [x] 5.3 Run `nix flake check` and verify that it passes, including all `host-*` checks and `u2f-pam`.
