# Spec Delta

## MODIFIED Requirements

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

## ADDED Requirements

### Requirement: NVIDIA pin follows the host driver
Before building, `nixos-central upgrade` (with or without `--private`) and the daily automatic home upgrade SHALL compare the NVIDIA driver loaded on the host with the version recorded in the local flake. If the flake records a driver and the versions differ, they SHALL record the loaded version and its hash in the flake. They MUST NOT add or remove a recorded driver, and MUST NOT need `--impure`.

#### Scenario: Host driver updated
- **WHEN** the local flake records NVIDIA driver 615.78.08, the host has loaded 620.70.06, and the user runs `nixos-central upgrade`
- **THEN** `~/.config/home-manager/flake.nix` records version 620.70.06 with its hash, and the activated home uses that driver

#### Scenario: Daily upgrade after a driver update
- **WHEN** the host's loaded NVIDIA driver differs from the recorded one and the daily automatic home upgrade runs
- **THEN** the flake records the loaded driver and its hash before the new home is built

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

### Requirement: Upgrade sets up changed GPU drivers
After `nixos-central upgrade` activates a home whose GPU drivers differ from those the system-wide GPU setup points to, it SHALL run that setup with `sudo` when its input and output are a terminal, and otherwise print the command to run. The daily automatic home upgrade MUST NOT run anything as root.

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

#### Scenario: Daily upgrade with changed drivers
- **WHEN** the daily automatic home upgrade activates a home whose GPU drivers differ from the system-wide setup
- **THEN** it logs the GPU setup command and runs nothing as root
