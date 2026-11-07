# Proposal

## Why

Today a private overlay can only be added after installation: the user has to get an SSH key onto the new machine, add it to GitHub, and run `nixos-central private setup`. On a freshly installed machine that usually means typing a key or copying files from another computer. Doing it in the installer — generate the key there, show it as a QR code to paste into GitHub from a phone, and install with the overlay — gives a fully personal machine on first boot. It also makes a generic profile from the overlay (e.g. `developer`) selectable for any username, which NixOS machines cannot do today.

## What Changes

- The installer optionally sets up a private overlay (prompt, or `--private <flake-url>`; default URL from `lib/default-private.nix`):
  - generates a passphrase-less ed25519 key for the primary user,
  - prints the public key as text and as a QR code in the terminal (`qrencode`), so it can be added to GitHub from a phone,
  - waits for confirmation, checks that the overlay can be read with that key (retry, or skip the overlay),
  - asks for a profile from the overlay's `homeModules` (or `--profile <name>`), defaulting to the username if the overlay has it, otherwise `default`,
  - installs the system with the overlay declared in `/etc/nixos/flake.nix` and the key in `/home/<user>/.ssh/id_ed25519`.
- `central.lib.mkHost` accepts an optional `profile`, with the same meaning as in `mkHome`: one name selects the central profile and the overlay profile; without it, the username is used as before.
- `nixos-central private setup --profile <name>` also works on NixOS: it records the profile in `/etc/nixos/flake.nix`. `nixos-central private remove` removes the recorded profile on NixOS together with the overlay.
- The summary at the end of the installation names the overlay and profile.
- Without an overlay, installation and existing machine flakes behave exactly as before.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `installer`: new flags `--private` and `--profile`; optional private overlay step with SSH key generation, QR code, access check and profile choice; summary includes overlay and profile.
- `private-overlay`: overlays can be set up during installation, not only afterwards; the overlay profile on NixOS is the recorded profile if one is set; `setup --profile` and `remove` work on NixOS too.
- `user-profiles`: a NixOS machine can record a profile name that is used instead of the primary user's name.
- `host-configuration`: the machine flake may record a profile; the host builder accepts it.

## Impact

- Code: `nixos-central-internal/installer/install.sh`, `nixos-central-internal/lib/default.nix` (`mkHost`/`hostModules`), `modules/options.nix`, `modules/user.nix`, `nixos-central-internal/private/nixos-central-private.sh`.
- Tests: `nixos-central-internal/tests/default.nix` (host builder with profile, `private-setup-failures`, `overlay-upgrades`), `nixos-central-internal/tests/overlay/flake.nix`, `nixos-central-internal/tests/e2e/run.py` (new prompt in existing runs, an install with overlay).
- Docs: README sections "Install", "Options", "What the installer does", "Users and profiles", "Private overlay".
- Dependency: builds on the in-progress change `add-unified-cli` (`nixos-central private` subcommand, default overlay URL), which should be archived first.
- Runtime: the live image fetches `qrencode` from the binary cache when the overlay step is used (network is already required).
