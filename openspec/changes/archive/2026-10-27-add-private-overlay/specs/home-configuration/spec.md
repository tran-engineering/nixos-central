# Spec Delta

## MODIFIED Requirements

### Requirement: Standalone home is a thin local flake
Each standalone home SHALL have a flake in `~/.config/home-manager` that consumes the central repository as an input named `central` and declares only facts: login name, home directory, platform, state version, chosen profile, and optional NVIDIA driver version and hash. It MAY additionally declare one private overlay as an input named `private` (see `private-overlay`). All other configuration MUST come from the central repository.

#### Scenario: Inspect a standalone home's config
- **WHEN** the user opens `~/.config/home-manager` on a machine set up by the home installer
- **THEN** it contains the local flake and its lock file, and the flake sets only the facts listed above, plus the private overlay if one was set up

#### Scenario: Rebuild from local flake
- **WHEN** the user runs `home-manager switch --flake ~/.config/home-manager`
- **THEN** the home is built from the locked revision of the central repository

### Requirement: Central repository exposes a home builder
The central repository SHALL expose a stable entry point that builds a standalone home from the facts of the local flake and an optional private overlay. Changes to the central repository MUST NOT require edits to existing local home flakes unless explicitly announced as breaking.

#### Scenario: State version stays fixed
- **WHEN** the central repository moves to a newer release
- **THEN** an existing standalone home keeps the state version recorded in its local flake

#### Scenario: Central change rolls out
- **WHEN** a profile changes in the central repository and a standalone home updates its `central` input
- **THEN** the home picks up the change without editing `~/.config/home-manager/flake.nix`

### Requirement: Daily automatic home upgrade
Each standalone home SHALL check daily for a newer revision of the central repository, update only the `central` input of its local flake and, if declared, the `private` input, and activate the result for the user. A run missed while the machine was off MUST run soon after the user is next logged in.

#### Scenario: Update available
- **WHEN** the central repository has new commits and the daily upgrade runs
- **THEN** `central` in `~/.config/home-manager/flake.lock` points to the new revision and the new home is active

#### Scenario: Build fails
- **WHEN** the new configuration fails to build
- **THEN** the previously active home stays active

#### Scenario: Overlay updated
- **WHEN** the home declares a private overlay with new commits and the daily upgrade runs
- **THEN** `private` in the lock file points to the new revision and its changes are active
