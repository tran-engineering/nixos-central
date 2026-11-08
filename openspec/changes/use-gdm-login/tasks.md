# Tasks

## 1. GDM for every graphical desktop

- [x] 1.1 Enable GDM in `modules/base/graphical.nix`; remove the display-manager settings from `modules/desktops/kde.nix`, `gnome.nix` and `niri-noctalia.nix` (keeping `defaultSession = "niri"`), delete `modules/base/sddm.nix` with its import and `modules/desktops/niri-noctalia/sddm-greeter.kdl`; update the module header comments. Verify that `ci-kde`, `ci-gnome` and `ci-niri-noctalia` evaluate with GDM on and SDDM off, `ci-none` with neither, the default session is `plasma` on kde and `niri` on niri-noctalia, and `pam.d/gdm-password` uses the `login` substack, whose text contains `pam_gnome_keyring` on niri-noctalia and `pam_kwallet5` on kde.
- [x] 1.2 Update `u2f-pam`: on every graphical desktop `gdm-password` has the key rule before the `login` substack, and the SDDM rule, its "kde with GDM" case and every other SDDM reference are removed from `u2f.nix` and the check. Verify `nix build .#checks.x86_64-linux.u2f-pam` passes.

## 2. Documentation and the open key-login change

- [x] 2.1 README: desktops table (GDM for all), replace the Catppuccin paragraph with a note on GDM (login-screen suspend and how to turn it off), adjust the "new desktop" paragraph, and the security-key table (touch prompt at GDM on every desktop). Verify no SDDM reference remains.
- [x] 2.2 Update `openspec/changes/add-u2f-login` (proposal, spec scenarios, design) to GDM as the login screen of every desktop; verify `openspec validate add-u2f-login --strict` passes.

## 3. Verification

- [x] 3.1 Run `nix flake check` and `nix build .#desktopTests.reboot-notify-kde` (logs in through GDM's auto-login); both pass.
- [ ] 3.2 On a real KDE and a niri-noctalia machine after upgrading and rebooting: GDM appears, logging in with the password starts Plasma or niri with Noctalia, the wallet or keyring is unlocked, and a key touch logs in after picking the account.
