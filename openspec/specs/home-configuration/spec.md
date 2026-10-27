# home-configuration Specification

## Purpose

Defines how a user environment on a Linux machine without NixOS is composed from the central repository plus a minimal per-user local flake, and how such a standalone home stays up to date.

## Requirements

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

### Requirement: Same packages as NixOS machines
A standalone home SHALL see the same package set a NixOS machine's user environment sees for the same central revision, including unfree packages and `pkgs.unstable`.

#### Scenario: Profile uses an unstable package
- **WHEN** a profile installs `pkgs.unstable.<name>`
- **THEN** the profile builds both on a NixOS machine and as a standalone home

### Requirement: Supported platforms
Standalone homes SHALL be supported on Linux distributions other than NixOS on `x86_64-linux` and `aarch64-linux`. Other operating systems are out of scope.

#### Scenario: ARM machine
- **WHEN** the home builder is used with platform `aarch64-linux`
- **THEN** it produces a home for that platform

### Requirement: GPU integration with the host
A standalone home SHALL make graphical programs from the central repository use the host's GPU drivers. The required system-wide setup MUST be a separate, one-time step that needs root and is only performed with the user's consent. Proprietary NVIDIA drivers SHALL be supported when the driver version and hash are recorded in the local flake.

#### Scenario: Mesa GPU after setup
- **WHEN** the one-time GPU setup has been run on a machine with an Intel or AMD GPU
- **THEN** graphical programs from the profile start with hardware acceleration

#### Scenario: NVIDIA driver recorded
- **WHEN** the local flake records the host's NVIDIA driver version and hash and the GPU setup has been run
- **THEN** graphical programs from the profile use the NVIDIA driver

#### Scenario: Setup declined
- **WHEN** the user declines the GPU setup
- **THEN** the home is still activated, and the user is told how to run the setup later

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

### Requirement: Rollback to the previous home
Previous home generations SHALL remain available so the user can switch back to the last working one if an update is broken.

#### Scenario: Broken update
- **WHEN** an update activates a broken home
- **THEN** the user can activate the previous generation with a documented command

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

### Requirement: Showing what the last home update changed
Each standalone home SHALL provide a command `nixos-central-diff`, run as the user without root, that lists the packages added, removed and changed in version from the previous home generation to the current one, names both generation numbers, and changes nothing.

#### Scenario: After an update
- **WHEN** the daily upgrade or `nixos-central-upgrade` has activated a new home generation and the user runs `nixos-central-diff`
- **THEN** the command lists the package changes from the previous generation to the current one

#### Scenario: No previous generation
- **WHEN** the home has only one generation and the user runs `nixos-central-diff`
- **THEN** the command says there is no earlier generation to compare with and succeeds

#### Scenario: Unknown argument
- **WHEN** the user runs `nixos-central-diff` with any argument
- **THEN** the command prints its usage, exits with an error and changes nothing
