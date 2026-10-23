# Spec Delta

## Purpose

Defines how a machine's system configuration is composed from the central repository plus a minimal set of machine-local facts, so all machines share one source of truth.

## ADDED Requirements

### Requirement: Machine configuration is a thin local flake
Each installed machine SHALL have a flake in `/etc/nixos` that consumes the central repository as an input named `central` and declares only machine facts: hostname, primary username, desktop, install disk, the NixOS release it was installed with (state version), and hardware configuration. All other system configuration MUST come from the central repository.

#### Scenario: Inspect a machine's config
- **WHEN** an administrator opens `/etc/nixos` on an installed machine
- **THEN** it contains the local flake, its lock file, and `hardware-configuration.nix`, and the flake sets only hostname, user, desktop, disk, state version, and hardware

#### Scenario: Rebuild from local flake
- **WHEN** a user runs `sudo nixos-rebuild switch --flake /etc/nixos`
- **THEN** the system builds using the locked revision of the central repository

### Requirement: Central repository exposes a host builder
The central repository SHALL expose a stable entry point that builds a complete NixOS system from hostname, primary username, desktop name, install disk, state version, and extra modules. Changes to the central repository MUST NOT require edits to existing machine flakes unless explicitly announced as breaking.

#### Scenario: State version stays fixed
- **WHEN** the central repository moves to a newer NixOS release
- **THEN** an existing machine keeps the state version recorded in its local flake

#### Scenario: Central change rolls out
- **WHEN** a shared module changes in the central repository and a machine updates its `central` input
- **THEN** the machine picks up the change without editing `/etc/nixos/flake.nix`

### Requirement: Desktop is selectable per machine
The central repository SHALL offer a set of named desktops, including `kde` and `none`. The machine flake's desktop value SHALL determine which desktop environment is enabled. An unknown desktop name MUST fail evaluation with a message listing valid names.

#### Scenario: KDE selected
- **WHEN** a machine flake sets desktop `kde`
- **THEN** the system boots into a graphical KDE Plasma login

#### Scenario: Change desktop later
- **WHEN** a user changes the desktop value in `/etc/nixos/flake.nix` to another offered desktop and rebuilds
- **THEN** the new desktop is active after rebuild

#### Scenario: Invalid desktop
- **WHEN** a machine flake sets desktop `foo`
- **THEN** evaluation fails and lists the valid desktop names

### Requirement: Shared base configuration
Every machine SHALL get a common base from the central repository: systemd-boot on UEFI, NetworkManager, flakes and the `nix` command enabled, and the configured hostname.

#### Scenario: Network on fresh install
- **WHEN** a freshly installed machine boots
- **THEN** the user can connect to Wi-Fi via NetworkManager without further configuration

### Requirement: Ad-hoc shells use the system's nixpkgs
`nix-shell -p <pkg>`, `nix shell nixpkgs#<pkg>`, and `nix run nixpkgs#<pkg>` SHALL resolve `nixpkgs` to the same nixpkgs revision the system was built from, without requiring channels.

#### Scenario: Try a package temporarily
- **WHEN** a user runs `nix-shell -p ripgrep`
- **THEN** a shell with `ripgrep` from the system's pinned nixpkgs opens, without downloading a different nixpkgs revision

#### Scenario: Flake-style shell
- **WHEN** a user runs `nix shell nixpkgs#hello`
- **THEN** `hello` is provided from the system's pinned nixpkgs
