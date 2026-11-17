# home-configuration Specification

## Purpose

Defines how a user environment on a Linux machine without NixOS is composed from the central repository plus a minimal per-user local flake, and how such a standalone home stays up to date.

## Requirements

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
A standalone home SHALL make graphical programs from the central repository use the host's GPU drivers. The required system-wide setup MUST be a separate step that needs root and is only performed with the user's consent; it is needed once, and again whenever the home's GPU drivers change. Proprietary NVIDIA drivers SHALL be supported when the driver version and hash are recorded in the local flake.

#### Scenario: Mesa GPU after setup
- **WHEN** the one-time GPU setup has been run on a machine with an Intel or AMD GPU
- **THEN** graphical programs from the profile start with hardware acceleration

#### Scenario: NVIDIA driver recorded
- **WHEN** the local flake records the host's NVIDIA driver version and hash and the GPU setup has been run
- **THEN** graphical programs from the profile use the NVIDIA driver

#### Scenario: Setup declined
- **WHEN** the user declines the GPU setup
- **THEN** the home is still activated, and the user is told how to run the setup later

### Requirement: Rollback to the previous home
Previous home generations SHALL remain available so the user can switch back to the last working one if an update is broken.

#### Scenario: Broken update
- **WHEN** an update activates a broken home
- **THEN** the user can activate the previous generation with a documented command

### Requirement: Upgrading the home immediately on demand
Each standalone home SHALL provide a subcommand `nixos-central upgrade`, run as the user without root, that updates the `central` input and, if declared, the `private` input of `~/.config/home-manager` to their latest revisions and activates the result. It MUST update no other input.

#### Scenario: Update available
- **WHEN** the central repository has new commits and the user runs `nixos-central upgrade`
- **THEN** `central` in `~/.config/home-manager/flake.lock` points to the new revision and the new home is active

#### Scenario: Overlay updated
- **WHEN** the home declares a private overlay with new commits and the user runs `nixos-central upgrade`
- **THEN** `private` in the lock file points to the new revision and its changes are active

#### Scenario: Already up to date
- **WHEN** the user runs `nixos-central upgrade` and both inputs are already at their latest revisions
- **THEN** the command succeeds and the active home is the current configuration

#### Scenario: Build fails
- **WHEN** the configuration fails to build, or the central repository or the private overlay cannot be fetched
- **THEN** the command fails with an error, and the active home, `~/.config/home-manager/flake.lock` and `~/.config/home-manager/flake.nix` are unchanged

#### Scenario: Unknown argument
- **WHEN** the user runs `nixos-central upgrade` with an argument other than `--private`
- **THEN** the command prints its usage, exits with an error and changes nothing

### Requirement: Upgrading only the home's overlay on demand
`nixos-central upgrade --private` on a standalone home SHALL update only the `private` input to its latest revision and activate the result; `central` MUST stay at its locked revision.

#### Scenario: Overlay changed, central changed too
- **WHEN** both the central repository and the overlay have new commits and the user runs `nixos-central upgrade --private`
- **THEN** `private` in the lock file points to the new overlay revision, `central` is unchanged, and the overlay's changes are active

#### Scenario: No overlay declared
- **WHEN** the home declares no private overlay and the user runs `nixos-central upgrade --private`
- **THEN** the command fails with an error saying the home has no private overlay, and changes nothing

### Requirement: Showing what the last home update changed
Each standalone home SHALL provide a subcommand `nixos-central diff`, run as the user without root, that lists the packages added, removed and changed in version from the previous home generation to the current one, names both generation numbers, and changes nothing.

#### Scenario: After an update
- **WHEN** the daily upgrade or `nixos-central upgrade` has activated a new home generation and the user runs `nixos-central diff`
- **THEN** the command lists the package changes from the previous generation to the current one

#### Scenario: No previous generation
- **WHEN** the home has only one generation and the user runs `nixos-central diff`
- **THEN** the command says there is no earlier generation to compare with and succeeds

#### Scenario: Unknown argument
- **WHEN** the user runs `nixos-central diff` with any argument
- **THEN** the command prints its usage, exits with an error and changes nothing

### Requirement: No automatic home upgrades
A standalone home MUST NOT update its flake inputs or activate a new home on its own. The `central` and `private` inputs in `~/.config/home-manager/flake.lock` SHALL change only when the user runs `nixos-central upgrade` or edits the flake.

#### Scenario: New commits in the central repository
- **WHEN** the central repository has new commits and the user stays logged in for several days without running `nixos-central upgrade`
- **THEN** `~/.config/home-manager/flake.lock` and the active home are unchanged

#### Scenario: Home installed before this change
- **WHEN** a home that had the daily `home-manager-auto-upgrade` timer runs `nixos-central upgrade` into a configuration with this change
- **THEN** the timer no longer exists afterwards

### Requirement: Upgrade keeps the NVIDIA pin in step with the host
Before building, `nixos-central upgrade` (with or without `--private`) SHALL compare the NVIDIA driver loaded on the host with the version recorded in the local flake. If the flake records a driver and the versions differ, it SHALL record the loaded version and its hash in the flake. It MUST NOT add or remove a recorded driver, and MUST NOT need `--impure`.

#### Scenario: Host driver updated
- **WHEN** the local flake records NVIDIA driver 615.78.08, the host has loaded 620.70.06, and the user runs `nixos-central upgrade`
- **THEN** `~/.config/home-manager/flake.nix` records version 620.70.06 with its hash, and the activated home uses that driver

#### Scenario: Driver unchanged
- **WHEN** the recorded NVIDIA driver version equals the loaded one
- **THEN** `~/.config/home-manager/flake.nix` is not modified and nothing is downloaded for the check

#### Scenario: No driver recorded
- **WHEN** the local flake records no NVIDIA driver (`nvidia = null`), even if the host has one loaded
- **THEN** the flake is not modified

#### Scenario: No driver loaded
- **WHEN** the local flake records an NVIDIA driver but no NVIDIA driver is loaded on the host
- **THEN** the flake is not modified and the upgrade continues with the recorded driver

#### Scenario: New driver cannot be fetched
- **WHEN** the versions differ but the new driver cannot be downloaded
- **THEN** a warning names the version that could not be fetched, the flake is not modified, and the upgrade continues with the recorded driver

#### Scenario: Flake of another shape
- **WHEN** the versions differ but the local flake does not contain exactly one `nvidia = …;` line as written by the home installer
- **THEN** a warning says the driver must be updated by hand, the flake is not modified, and the upgrade continues

### Requirement: Upgrade runs the GPU setup for changed drivers
After `nixos-central upgrade` activates a home whose GPU drivers differ from those the system-wide GPU setup points to, it SHALL run that setup with `sudo` when its input and output are a terminal, and otherwise print the command to run.

#### Scenario: Drivers changed, interactive
- **WHEN** the user runs `nixos-central upgrade` in a terminal and the activated home's GPU drivers differ from the system-wide setup
- **THEN** the command runs the GPU setup with `sudo`, which asks for the user's password

#### Scenario: Setup refused or fails
- **WHEN** the user cancels the `sudo` prompt or the GPU setup fails
- **THEN** the upgrade still counts as installed, and the command prints how to run the GPU setup later

#### Scenario: Drivers changed, no terminal
- **WHEN** `nixos-central upgrade` runs without a terminal and the drivers differ
- **THEN** nothing runs as root and the command prints the GPU setup command

#### Scenario: Drivers unchanged
- **WHEN** the system-wide GPU setup already points to the activated home's drivers
- **THEN** the command does not run or mention the GPU setup
