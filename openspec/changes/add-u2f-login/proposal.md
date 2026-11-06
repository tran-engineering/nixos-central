# Proposal

## Why

Users of nixos-central machines who own a FIDO2/U2F security key (e.g. a YubiKey) have to type their password at the login screen and at every screen unlock. Signing in with a key touch is faster, and it avoids typing the password while someone is watching. Today, every user has to configure this by hand outside the central repository. The repository has no PAM U2F configuration.

## What Changes

- Every NixOS machine supports signing in with a U2F/FIDO2 security key **as an alternative to the password**. The key is accepted at the graphical login screen and at the lock screen of each desktop:
  - KDE: SDDM login and the KDE lock screen
  - GNOME: GDM login and the GNOME lock screen
  - niri-noctalia: SDDM login and Noctalia's lock screen
- The password keeps working everywhere. Users who never enroll a key notice no difference apart from the absence of the "touch your key" prompt.
- TTY (console) login and `sudo` stay password-only.
- Enrollment is per user and manual. The user runs `pamu2fcfg` once and stores the result in `~/.config/Yubico/u2f_keys`. Keys are bound to one fleet-wide origin, so the same file works on every nixos-central machine of that user.
- The README documents enrollment, a backup key, and how to remove a key.
- Machines with desktop `none` get no U2F login, because they have no display manager or lock screen.

## Capabilities

### New Capabilities
- `security-key-login`: signing in and unlocking graphical sessions with a U2F/FIDO2 security key as an alternative to the password. Covers which entry points accept the key, which stay password-only, the enrollment location, and portability across the user's machines.

### Modified Capabilities
<!-- None. The user-profiles "Primary user account" requirement (login with the install-time password, sudo works) stays true unchanged. -->

## Impact

- **Code**: a new `modules/base/u2f.nix` imported from `modules/base/default.nix`. It changes the PAM stacks of `sddm`, `gdm-password` and `kde`, and adds a dedicated PAM service for Noctalia's lock screen. `modules/desktops/niri-noctalia.nix` sets `NOCTALIA_PAM_SERVICE` for the Noctalia service.
- **Packages**: `pam_u2f` (provides `pamu2fcfg`) is installed system-wide on graphical machines. No extra udev rules are needed, because systemd already grants the seat user access to FIDO devices.
- **Tests**: new checks in `nixos-central-internal/tests` assert which PAM services contain `pam_u2f` and which do not.
- **Docs**: a new README section.
- **Security**: anyone who holds an enrolled key can unlock that user's graphical session without the password, and no PIN is required. The user accepted this trade-off for convenience. It is documented in the README, together with how to remove a lost key.
