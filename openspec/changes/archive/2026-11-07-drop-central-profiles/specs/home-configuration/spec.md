# Spec Delta

## MODIFIED Requirements

### Requirement: Standalone home is a thin local flake
Each standalone home SHALL have a flake in `~/.config/home-manager` that consumes the central repository as an input named `central` and declares only facts: login name, home directory, platform, state version, and optional NVIDIA driver version and hash. It MAY additionally declare one private overlay as an input named `private` (see `private-overlay`) and, together with it, the overlay profile to use. All other configuration MUST come from the central repository and the overlay. Local flakes written by earlier home installers, which record a profile without an overlay, MUST keep building.

#### Scenario: Inspect a standalone home's config
- **WHEN** the user opens `~/.config/home-manager` on a machine set up by the home installer
- **THEN** it contains the local flake and its lock file, and the flake sets only the facts listed above, without a profile, plus the private overlay and its profile if one was set up

#### Scenario: Rebuild from local flake
- **WHEN** the user runs `home-manager switch --flake ~/.config/home-manager`
- **THEN** the home is built from the locked revision of the central repository

### Requirement: Central repository exposes a home builder
The central repository SHALL expose a stable entry point that builds a standalone home from the facts of the local flake and an optional private overlay. Changes to the central repository MUST NOT require edits to existing local home flakes unless explicitly announced as breaking.

#### Scenario: State version stays fixed
- **WHEN** the central repository moves to a newer release
- **THEN** an existing standalone home keeps the state version recorded in its local flake

#### Scenario: Central change rolls out
- **WHEN** the base configuration or a shared module changes in the central repository and a standalone home updates its `central` input
- **THEN** the home picks up the change without editing `~/.config/home-manager/flake.nix`
