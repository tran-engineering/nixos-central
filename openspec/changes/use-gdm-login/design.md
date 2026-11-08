# Design

## Context

See proposal.md (Why). Current state:

- `modules/desktops/kde.nix` and `niri-noctalia.nix` enable SDDM;
  `gnome.nix` enables GDM. `modules/base/sddm.nix` themes SDDM (Catppuccin,
  cursor, font) whenever SDDM is enabled; niri's SDDM greeter runs under niri
  with `niri-noctalia/sddm-greeter.kdl`, and niri sets
  `security.pam.services.sddm.enableGnomeKeyring` itself.
- `modules/base/u2f.nix` puts its rule on the PAM service of the enabled
  display manager (`sddm` or `gdm-password`); with GDM only, it goes on
  `gdm-password` directly.
- `gdm-password` runs the `login` stack as a substack (auth, password) and
  includes it (session). Whatever `login` unlocks, GDM unlocks too: KWallet
  on kde (`pam_kwallet5`), gnome-keyring on niri-noctalia
  (`pam_gnome_keyring`).
- Tried on a real KDE machine with SDDM forced off and GDM on: Plasma starts,
  key and password login work, KWallet opens with the password.

## Goals / Non-Goals

**Goals:**
- One login screen for all graphical desktops, set in one place.
- No machine flake edits; machines switch at the next reboot after upgrading.

**Non-Goals:**
- Theming GDM.
- Any SDDM support: no theme, no PAM rule, no instructions for turning it
  back on. One login screen avoids confusing users.
- The extra click at KDE's lock screen with a key (a separate topic).

## Decisions

### D1: GDM is enabled in `modules/base/graphical.nix`
`services.displayManager.gdm.enable = true` moves from `gnome.nix` into the
shared module for every desktop except `none`, next to sound, Bluetooth and
printing. The desktop modules keep only what is specific to them
(`defaultSession = "niri"` on niri-noctalia).
- *Alternative*: enable GDM in each of the three desktop modules. Rejected:
  three copies of the same line, and a new desktop could forget it.

### D2: Remove the SDDM theming instead of keeping it dormant
`modules/base/sddm.nix` and `niri-noctalia/sddm-greeter.kdl` are deleted, as
are niri's SDDM greeter settings and its `sddm.enableGnomeKeyring`.
- *Alternative*: keep `sddm.nix` (it only acts when SDDM is enabled). Rejected
  by the user: it would be maintained for no default machine.

### D3: Keep GDM's defaults, including suspend at the login screen
`autoSuspend` stays on (GDM suspends after about 20 minutes idle at the login
screen, as GNOME machines already do). One behavior for all desktops; it can
be turned off per machine with
`services.displayManager.gdm.autoSuspend = false`.

### D4: gnome-keyring on niri via GDM's own wiring
niri enables gnome-keyring, which turns on `login.enableGnomeKeyring`, so
`login` contains `pam_gnome_keyring`, and `gdm-password` reaches it through its
`login` substack. The explicit `sddm.enableGnomeKeyring` that niri needed for
SDDM has no GDM counterpart. Verified by evaluation (task 1.1).

## Risks / Trade-offs

- [Machines left at the login screen now suspend] → D3; documented in the
  README with the override.
- [Overlays or machines that set an SDDM theme] → The option still exists and
  evaluates; it just has no effect while SDDM is off. Documented in the
  proposal as a breaking look change.
- [GNOME Shell on KDE and niri machines for the login screen: more disk use]
  → Accepted for the working key prompt.
- [GDM login on niri untested on hardware] → Manual check in the tasks; the
  desktop VM test for niri logs in through GDM's auto-login.

## Migration Plan

Nothing to do on machines: the next upgrade stages GDM, the reboot after it
uses it. Rollback: boot the previous generation, or revert the change.
