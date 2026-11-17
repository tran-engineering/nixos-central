## ADDED Requirements

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

## REMOVED Requirements

### Requirement: NVIDIA pin follows the host driver
**Reason**: Also covered the daily automatic home upgrade, which is gone; replaced by "Upgrade keeps the NVIDIA pin in step with the host", which covers `nixos-central upgrade` only, with otherwise unchanged behavior.
**Migration**: None.

### Requirement: Upgrade sets up changed GPU drivers
**Reason**: Also covered the daily automatic home upgrade, which is gone; replaced by "Upgrade runs the GPU setup for changed drivers", with otherwise unchanged behavior.
**Migration**: None.

### Requirement: Daily automatic home upgrade
**Reason**: Standalone homes no longer update themselves; users decide when to update.
**Migration**: Run `nixos-central upgrade`. New terminals say how long ago the last update was and show this command (see `stale-update-notice`).

### Requirement: No concurrent home upgrades
**Reason**: There is no automatic home upgrade left for `nixos-central upgrade` to collide with.
**Migration**: None.
