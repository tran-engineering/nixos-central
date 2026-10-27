# Spec Delta

## MODIFIED Requirements

### Requirement: Machine configuration is a thin local flake
Each installed machine SHALL have a flake in `/etc/nixos` that consumes the central repository as an input named `central` and declares only machine facts: hostname, primary username, desktop, install disk, the NixOS release it was installed with (state version), and hardware configuration. It MAY additionally declare one private overlay as an input named `private` (see `private-overlay`). All other system configuration MUST come from the central repository.

#### Scenario: Inspect a machine's config
- **WHEN** an administrator opens `/etc/nixos` on an installed machine
- **THEN** it contains the local flake, its lock file, and `hardware-configuration.nix`, and the flake sets only hostname, user, desktop, disk, state version, and hardware, plus the private overlay if one was set up

#### Scenario: Rebuild from local flake
- **WHEN** a user runs `sudo nixos-rebuild switch --flake /etc/nixos`
- **THEN** the system builds using the locked revision of the central repository

### Requirement: Central repository exposes a host builder
The central repository SHALL expose a stable entry point that builds a complete NixOS system from hostname, primary username, desktop name, install disk, state version, extra modules, and an optional private overlay. Changes to the central repository MUST NOT require edits to existing machine flakes unless explicitly announced as breaking.

#### Scenario: State version stays fixed
- **WHEN** the central repository moves to a newer NixOS release
- **THEN** an existing machine keeps the state version recorded in its local flake

#### Scenario: Central change rolls out
- **WHEN** a shared module changes in the central repository and a machine updates its `central` input
- **THEN** the machine picks up the change without editing `/etc/nixos/flake.nix`

#### Scenario: Machine without overlay
- **WHEN** an existing machine flake doesn't pass a private overlay
- **THEN** it builds exactly as before
