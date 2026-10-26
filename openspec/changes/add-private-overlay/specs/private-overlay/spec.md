# Spec Delta

## Purpose

Lets a user keep private parts of their configuration in a private repository they control and add them to their machines after installation, while the central repository and the installation stay public and anonymous.

## ADDED Requirements

### Requirement: Private overlay is a module-only flake
A private overlay SHALL be a flake that exports a home-manager module for the primary user and MAY export a NixOS module. It MUST NOT declare inputs of its own, so that packages and options always come from the central repository.

#### Scenario: Overlay adds private files
- **WHEN** the overlay's home module places `~/.ssh/config` and scripts in `~/.local/bin`
- **THEN** after setup, the user has these files in addition to everything from their profile

#### Scenario: Overlay declares inputs
- **WHEN** an overlay flake declares an input
- **THEN** building with it fails with a message that overlays must not have inputs

### Requirement: Overlay is added after installation by one command
The system SHALL provide a command `nixos-central-private setup <flake-url>` that verifies the repository can be read with the user's SSH key, adds the overlay to the local flake (machine or standalone home), and activates the result. It MUST change nothing if the repository can't be read.

#### Scenario: Setup on a fresh machine
- **WHEN** a user has copied their SSH key to `~/.ssh` and runs `nixos-central-private setup git+ssh://git@github.com/alice/private`
- **THEN** the local flake declares the overlay, and the overlay's files are active

#### Scenario: No access
- **WHEN** the user's SSH key can't read the repository
- **THEN** the command fails with a message naming the key it tried, and the local flake is unchanged

#### Scenario: Standalone home
- **WHEN** a user of a standalone home runs the setup command
- **THEN** the overlay is added to `~/.config/home-manager` and the home is switched

### Requirement: Overlay can be removed
`nixos-central-private remove` SHALL remove the overlay from the local flake and activate the configuration without it.

#### Scenario: Remove
- **WHEN** a user runs `nixos-central-private remove`
- **THEN** the local flake no longer declares the overlay and the overlay's files are gone after activation

### Requirement: Unattended upgrades can fetch the overlay
On NixOS machines, the automatic upgrade SHALL fetch the overlay with the primary user's SSH key without user interaction. GitHub's host keys SHALL be known in advance, so no host-key prompt can block a fetch.

#### Scenario: Daily upgrade with overlay
- **WHEN** the overlay repository has new commits and the daily upgrade runs while nobody is logged in
- **THEN** the staged generation contains the new overlay revision

### Requirement: Overlay failures stop updates instead of dropping the overlay
If a machine with an overlay can't fetch it, every upgrade MUST fail without changing the running system, the boot entries or the lock file. A configuration without the overlay MUST NOT be built in its place.

#### Scenario: Key revoked
- **WHEN** the SSH key is no longer accepted by GitHub and the daily upgrade runs
- **THEN** the upgrade fails, the overlay's files stay in place, and the failure is visible in the upgrade service's status

### Requirement: Overlays select shared modules by name
An overlay's modules SHALL be able to include any shared home module of the central repository by its name, without a path into the central repository. The set of names is an interface of the central repository; renaming or removing a name MUST be announced as breaking.

#### Scenario: Overlay uses shared modules
- **WHEN** an overlay's home module includes the shared `fish` and `dev-cli` modules by name
- **THEN** after setup, the user has the tools and settings of both modules

#### Scenario: New shared module
- **WHEN** a shared module is added to the central repository
- **THEN** overlays can include it by its name after their next update
