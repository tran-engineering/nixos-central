# Spec Delta

## ADDED Requirements

### Requirement: Upgrading the home immediately on demand
Each standalone home SHALL provide a command `nixos-central-upgrade`, run as the user without root, that updates the `central` input and, if declared, the `private` input of `~/.config/home-manager` to their latest revisions and activates the result. It MUST update no other input.

#### Scenario: Update available
- **WHEN** the central repository has new commits and the user runs `nixos-central-upgrade`
- **THEN** `central` in `~/.config/home-manager/flake.lock` points to the new revision and the new home is active

#### Scenario: Overlay updated
- **WHEN** the home declares a private overlay with new commits and the user runs `nixos-central-upgrade`
- **THEN** `private` in the lock file points to the new revision and its changes are active

#### Scenario: Already up to date
- **WHEN** the user runs `nixos-central-upgrade` and both inputs are already at their latest revisions
- **THEN** the command succeeds and the active home is the current configuration

#### Scenario: Build fails
- **WHEN** the configuration fails to build, or the central repository or the private overlay cannot be fetched
- **THEN** the command fails with an error, and the active home and `~/.config/home-manager/flake.lock` are unchanged

#### Scenario: Unknown argument
- **WHEN** the user runs `nixos-central-upgrade` with an argument other than `--private`
- **THEN** the command prints its usage, exits with an error and changes nothing

### Requirement: Upgrading only the home's overlay on demand
`nixos-central-upgrade --private` on a standalone home SHALL update only the `private` input to its latest revision and activate the result; `central` MUST stay at its locked revision.

#### Scenario: Overlay changed, central changed too
- **WHEN** both the central repository and the overlay have new commits and the user runs `nixos-central-upgrade --private`
- **THEN** `private` in the lock file points to the new overlay revision, `central` is unchanged, and the overlay's changes are active

#### Scenario: No overlay declared
- **WHEN** the home declares no private overlay and the user runs `nixos-central-upgrade --private`
- **THEN** the command fails with an error saying the home has no private overlay, and changes nothing

### Requirement: No concurrent home upgrades
`nixos-central-upgrade` on a standalone home MUST refuse to start while the daily automatic home upgrade is running, with an error that says so, and MUST change nothing in that case.

#### Scenario: Automatic upgrade in progress
- **WHEN** the user runs `nixos-central-upgrade` while the daily automatic home upgrade is running
- **THEN** the command exits with an error explaining that an upgrade is already in progress, and the active home and lock file are unchanged
