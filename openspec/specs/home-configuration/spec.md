# home-configuration Specification

## Purpose

Defines how a user environment on a Linux machine without NixOS is composed from the central repository plus a minimal per-user local flake, and how such a standalone home stays up to date.

## Requirements

### Requirement: Standalone home is a thin local flake
Each standalone home SHALL have a flake in `~/.config/home-manager` that consumes the central repository as an input named `central` and declares only facts: login name, home directory, platform, state version, chosen profile, and optional NVIDIA driver version and hash. All other configuration MUST come from the central repository.

#### Scenario: Inspect a standalone home's config
- **WHEN** the user opens `~/.config/home-manager` on a machine set up by the home installer
- **THEN** it contains the local flake and its lock file, and the flake sets only the facts listed above

#### Scenario: Rebuild from local flake
- **WHEN** the user runs `home-manager switch --flake ~/.config/home-manager`
- **THEN** the home is built from the locked revision of the central repository

### Requirement: Central repository exposes a home builder
The central repository SHALL expose a stable entry point that builds a standalone home from the facts of the local flake. Changes to the central repository MUST NOT require edits to existing local home flakes unless explicitly announced as breaking.

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
Each standalone home SHALL check daily for a newer revision of the central repository, update only the `central` input of its local flake, and activate the result for the user. A run missed while the machine was off MUST run soon after the user is next logged in.

#### Scenario: Update available
- **WHEN** the central repository has new commits and the daily upgrade runs
- **THEN** `central` in `~/.config/home-manager/flake.lock` points to the new revision and the new home is active

#### Scenario: Build fails
- **WHEN** the new configuration fails to build
- **THEN** the previously active home stays active

### Requirement: Rollback to the previous home
Previous home generations SHALL remain available so the user can switch back to the last working one if an update is broken.

#### Scenario: Broken update
- **WHEN** an update activates a broken home
- **THEN** the user can activate the previous generation with a documented command
