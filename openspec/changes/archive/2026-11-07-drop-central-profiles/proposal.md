# Proposal

## Why

Personal configuration now lives in private overlays (commit "move most things to private"). The `users/` directory at the top level of the central repository no longer contains a personal profile. It only contains the shared default profile `_default`, which every user gets as the base, and two test profiles, `ci-user` and `ci-modules`. The top-level directory and the "central personal profile" concept still suggest that a user customizes their environment by adding `users/<name>`, and `home-only.sh` still asks for a central profile. Both are misleading. Test fixtures belong with the other tests in `nixos-central-internal/`.

## What Changes

- **BREAKING** The central repository no longer has personal profiles. The `users/` directory is removed. Profiles exist only in private overlays (`homeModules.<name>`).
- The content of `users/_default` becomes the **base home configuration**, `modules/home/base.nix`. Every primary user on a NixOS machine and every standalone home gets it, with or without an overlay. Its settings are defaults that an overlay profile can override without `mkForce`. It is internal and is not offered as a shared module in `centralModules`.
- The test profiles `ci-user` and `ci-modules` move to `nixos-central-internal/tests/profiles/`. Only the CI configurations in `flake.nix` use them. They are added through an internal builder, not through `mkHost` or `mkHome` arguments.
- A recorded profile name (`profile = "…";` in a machine flake or home flake) only selects the **overlay** profile. Without an overlay, a recorded profile has no effect and the build warns about it. The value `_default`, which `home-only.sh` used to write, is ignored without a warning.
- **BREAKING** `home-only.sh` no longer asks for a profile and no longer accepts `--profile`. Given that flag, it aborts and points to `nixos-central private setup --profile NAME`. The home flake template no longer contains a `profile` line. `nixos-central private setup --profile` adds the line, and `private remove` deletes it again, on standalone homes as on NixOS.
- `lib.profileNames` and `nixos-central-internal/lib/profiles.nix` are removed. Nothing outside this repository uses them.
- `mkHost` and `mkHome` keep their signatures, including `profile`. Existing machine and home flakes keep building unchanged.
- CI: the `home-profile-<name>` checks and the `ci-default-profile` host are removed. The `host-profile` and `overlay-profiles` checks are rewritten for overlay-only profiles. The e2e test's `try`/`upgrade` steps change the base configuration of the served central repository instead of writing `users/alice`.
- README: the sections "Users and profiles", "How a machine is configured", home-only options, "Private overlay" and "Development" are updated.

Out of scope: setting up a private overlay from `home-only.sh` (like `install.sh --private`). For now, standalone homes add an overlay after installation with `nixos-central private setup`.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `user-profiles`: The shared default profile becomes the base configuration that every user always gets. Personal profiles, the fallback logic, the selectable-profile list and central customization are replaced by overlay profiles on top of the base. A recorded profile on NixOS and on standalone homes selects only the overlay profile.
- `home-installer`: The home installer no longer selects a central profile and rejects `--profile`. Its summary no longer names a profile.
- `home-configuration`: The local home flake records a profile only together with an overlay. The template has no profile line.
- `private-overlay`: The overlay profile is chosen by the recorded profile or the user's name, no longer "like a central profile". The user gets the base configuration plus the overlay profile. `remove` drops the recorded profile on standalone homes too.
- `home-modules`: References to the shared default profile and to selectable profiles become references to the base configuration. The all-modules test profile is a test fixture, not a central profile.

## Impact

- **Code**: `users/` is removed. New: `modules/home/base.nix` and `nixos-central-internal/tests/profiles/{ci-user,ci-modules}/`. Changed: `modules/user.nix`, `nixos-central-internal/lib/{default.nix,overlay.nix}`, `nixos-central-internal/lib/profiles.nix` (removed), `nixos-central-internal/installer/home-only.sh`, `nixos-central-internal/templates/home/flake.nix`, `nixos-central-internal/private/flake-edit.sh` and its usage text, `flake.nix` (CI configurations and checks), `nixos-central-internal/tests/{default.nix,e2e/run.py}`, and `.github/workflows/ci.yml` (`--profile _default`).
- **Existing machines**: they keep building. The base configuration replaces the `_default` fallback with the same content. On NixOS, users who never set these options get the same result. Values that were plain become `mkDefault`, so overlays that currently set the same option with `mkForce` keep working.
- **Existing standalone homes**: `profile = "_default"` keeps working without a warning. Any other recorded profile without an overlay warns, but the home still builds.
- **Ordering**: `add-private-overlay-at-install` must be archived first. This change's deltas modify requirements that change adds or rewrites (`NixOS machines can record a profile`, `Overlay profile is chosen like a central profile`, `Overlay can be removed`).
