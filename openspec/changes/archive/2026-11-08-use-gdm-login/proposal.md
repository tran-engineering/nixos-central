# Proposal

## Why

Signing in with a security key (change `add-u2f-login`) works poorly on SDDM:
no SDDM theme (including Catppuccin, Breeze and SDDM's own) shows PAM's
"Please touch the device." message, and the check only starts after pressing
Enter on an empty password field. Users can't tell when to touch the key, and
a touch at the wrong moment types the YubiKey's one-time code into the field.
GDM starts the check as soon as an account is picked and shows the prompt.
Tried on a KDE machine with GDM: key and password login both work.

## What Changes

- Every graphical desktop (`kde`, `gnome`, `niri-noctalia`) uses GDM as its
  login screen. `kde` and `niri-noctalia` no longer use SDDM.
- **BREAKING** (look): the Catppuccin SDDM theme and cursor, and the
  niri-based SDDM greeter, are removed. Machines that set an SDDM theme in
  their own modules or overlay lose it; SDDM is no longer supported.
- `niri-noctalia` keeps starting a niri session by default; `kde` starts
  Plasma.
- Security-key login moves with it: its PAM rule goes on `gdm-password` only.
- Machines pick the change up with the next upgrade and use GDM after the
  next reboot; no edits to machine flakes.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `host-configuration`: the "Desktop is selectable per machine" scenarios
  name GDM as the login screen of `kde` and `niri-noctalia`.

## Impact

- `modules/base/graphical.nix` (or the desktop modules): GDM for every
  graphical desktop; `modules/desktops/kde.nix`, `niri-noctalia.nix`,
  `gnome.nix` lose their own display-manager settings.
- Removed: `modules/base/sddm.nix`, `modules/desktops/niri-noctalia/sddm-greeter.kdl`.
- `nixos-central-internal/tests/default.nix`: `u2f-pam` expects
  `gdm-password` on every graphical desktop; desktop tests log in through GDM.
- README: desktops table and theme paragraph, security-key table.
- The open change `add-u2f-login`: its spec scenarios and design mention SDDM
  and are updated to GDM.
- KDE and niri machines get GNOME Shell for the login screen (a few hundred
  MB more).
