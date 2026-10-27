# Proposal

## Why

The central repository is public and should hold only what is useful to anyone: the base system, desktops and shared modules. A user's personal configuration (which modules they pick, identity, fonts and themes, and private parts such as work SSH configuration and internal scripts) belongs to the user, and some of it must not be public. Encrypting that into the public repository or making the repository private would put credentials into the installation path. Instead, the install stays anonymous, and a machine can add **one private overlay** afterwards: a flake in a private repository the user controls, reachable with the user's own SSH key.

## What Changes

- A machine flake (`/etc/nixos`) or standalone home flake (`~/.config/home-manager`) can declare an optional input `private` and pass it to `mkHost`/`mkHome`. The overlay's home module is added to the primary user's profile; an optional NixOS module is added to the system.
- The overlay is a flake **without inputs** that only exports modules (`homeModules.default`, optionally `nixosModules.default`). Packages and options still come from central.
- Overlays select central's shared home modules by name through a `centralModules` argument (e.g. `imports = with centralModules; [ dev-cli fish ];`), since they can't import central's files by path. These names become a stable interface of central.
- Personal configuration belongs in the overlay, not in central: `users/kt` is removed from central and its content moves to kt's private overlay. A test-only profile `users/ci-modules` takes over CI coverage of the shared modules.
- A command `nixos-central-private` does the setup after first boot: `setup <flake-url>` checks the key can read the repository, adds the input, and rebuilds. `remove` takes it out again.
- Daily and on-demand upgrades update `private` together with `central`. If the private repository can't be fetched, the upgrade fails and changes nothing (fail closed). It never builds without the overlay.
- On NixOS, root uses the primary user's SSH key (default `~/.ssh/id_ed25519`) for GitHub, so unattended upgrades can fetch the overlay. Central pins GitHub's public host keys.
- **BREAKING (spec only, no migration needed):** the rule that local flakes must not add a user-level customization layer is relaxed to allow exactly this one overlay.

## Capabilities

### New Capabilities
- `private-overlay`: what a private overlay is and may contain, how it selects central's shared modules, how it's set up and removed, how unattended upgrades reach it, and how failures behave.

### Modified Capabilities
- `user-profiles`: customization lives in central, plus at most one private overlay.
- `host-configuration`: the machine flake may declare `private`; `mkHost` accepts it.
- `home-configuration`: the standalone home flake may declare `private`; `mkHome` accepts it; the daily home upgrade also updates it.
- `system-updates`: the daily upgrade and `nixos-central-upgrade` also update `private` when it is declared.
- `home-modules`: shared modules are verified through a test profile instead of a personal one.

## Impact

- `nixos-central-internal/lib/default.nix`: `mkHost`/`mkHome` get an optional `private` argument (backwards compatible).
- `modules/base`: the upgrade flags depend on whether an overlay exists. Root's SSH setup for GitHub, the GitHub known host keys, and the `nixos-central-private` command.
- `modules/home/standalone.nix`: home auto-upgrade also updates `private`, and the command is available.
- `users/kt` removed, `users/ci-modules` added. The kt-based checks (`host-eval-kt`, `ci-home-kt-aarch64`) move to it. Until kt's overlay is set up, user `kt` gets the default profile.
- Templates are unchanged (no overlay by default). The command edits existing local flakes in the template's shape.
- Security: the user's personal SSH key is used by root for fetches from GitHub. Losing a machine means rotating that key.
