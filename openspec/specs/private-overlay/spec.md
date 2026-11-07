# private-overlay Specification

## Purpose

Lets a user keep private parts of their configuration in a private repository they control and add them to their machines, during installation or afterwards, while the central repository and the installer stay public and anonymous.

## Requirements

### Requirement: Private overlay is a module-only flake
A private overlay SHALL be a flake that exports home-manager modules, one per profile, and MAY export a NixOS module. It MUST NOT declare inputs of its own, so that packages and options always come from the central repository.

#### Scenario: Overlay adds private files
- **WHEN** the overlay's profile for the user places `~/.ssh/config` and scripts in `~/.local/bin`
- **THEN** after setup, the user has these files in addition to everything from the central base configuration

#### Scenario: Overlay declares inputs
- **WHEN** an overlay flake declares an input
- **THEN** building with it fails with a message that overlays must not have inputs

### Requirement: Overlay profile is chosen by the recorded profile or the user's name
The overlay profile SHALL be chosen by name: on a NixOS machine the profile recorded in its machine flake, or the primary user's name if none is recorded; on a standalone home the profile recorded in its local flake, or the login name if none is recorded. If the overlay has no profile of that name, its default profile SHALL be used; if that name was recorded, the build MUST warn about it. If the overlay has neither, the build MUST fail with a message listing the overlay's profiles.

#### Scenario: Several users in one overlay
- **WHEN** the overlay has profiles `kt` and `ft`, and machine `foo` has primary user `ft` and no recorded profile
- **THEN** `ft`'s environment on `foo` gets the overlay's `ft` profile and nothing from `kt`

#### Scenario: Recorded profile on NixOS
- **WHEN** the overlay has profiles `default` and `developer`, and machine `foo` has primary user `alice` and records profile `developer`
- **THEN** `alice`'s environment on `foo` gets the overlay's `developer` profile

#### Scenario: Fallback to the overlay's default
- **WHEN** the overlay has a default profile but none of the chosen name
- **THEN** the user gets the overlay's default profile, with a warning only if the name was recorded

#### Scenario: No matching profile
- **WHEN** the overlay has neither a profile of the chosen name nor a default profile
- **THEN** the build fails and the message lists the overlay's profiles

### Requirement: Overlay is added after installation by one command
The system SHALL provide a subcommand `nixos-central private setup [<flake-url>] [--profile <name>]` that verifies the repository can be read with the user's SSH key, adds the overlay to the local flake (machine or standalone home), optionally records the profile name, and activates the result. It MUST change nothing if the repository can't be read. An overlay set up during installation (see `installer`) SHALL result in the same local flake as this command.

#### Scenario: Setup on a fresh machine
- **WHEN** a user has copied their SSH key to `~/.ssh` and runs `nixos-central private setup git+ssh://git@github.com/alice/private`
- **THEN** the local flake declares the overlay, and the overlay's files are active

#### Scenario: No access
- **WHEN** the user's SSH key can't read the repository
- **THEN** the command fails with a message naming the key it tried, and the local flake is unchanged

#### Scenario: Standalone home
- **WHEN** a user of a standalone home runs the setup command
- **THEN** the overlay is added to `~/.config/home-manager` and the home is switched

#### Scenario: Standalone home with an overlay-only profile
- **WHEN** a user of a standalone home installed without a profile runs the setup command with `--profile kt`, and the overlay has a `kt` profile
- **THEN** the local flake records profile `kt`, the user gets the central base configuration plus the overlay's `kt` profile, and no warning is shown

#### Scenario: NixOS machine with an overlay-only profile
- **WHEN** primary user `alice` of a NixOS machine runs `nixos-central private setup git+ssh://git@github.com/alice/private --profile developer`, and the overlay has a `developer` profile
- **THEN** `/etc/nixos/flake.nix` declares the overlay and records profile `developer`, and after activation `alice` has the central base configuration plus the overlay's `developer` profile

#### Scenario: Default overlay
- **WHEN** a user runs `nixos-central private setup` without a flake URL
- **THEN** the command says it uses the default overlay and sets up `git+ssh://git@github.com/tran-engineering/nixos-central-private`, as if that URL had been given

#### Scenario: Default overlay with a profile
- **WHEN** a user runs `nixos-central private setup --profile kt`
- **THEN** the default overlay is set up with profile `kt`

### Requirement: Overlay can be removed
`nixos-central private remove` SHALL remove the overlay and a recorded profile from the local flake, on NixOS machines and standalone homes alike, and activate the configuration without them.

#### Scenario: Remove
- **WHEN** a user runs `nixos-central private remove`
- **THEN** the local flake no longer declares the overlay and the overlay's files are gone after activation

#### Scenario: Remove on NixOS with a recorded profile
- **WHEN** a NixOS machine with primary user `alice` declares an overlay and records profile `developer`, and `alice` runs `nixos-central private remove`
- **THEN** `/etc/nixos/flake.nix` declares neither the overlay nor a profile, and the machine builds with the base configuration, without a warning

#### Scenario: Remove on a standalone home with a recorded profile
- **WHEN** a standalone home declares an overlay and records profile `kt`, and its user runs `nixos-central private remove`
- **THEN** `~/.config/home-manager/flake.nix` declares neither the overlay nor a profile, and the home builds with the base configuration, without a warning

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
- **WHEN** an overlay's home module includes the shared `zsh` and `git` modules by name
- **THEN** after setup, the user has the tools and settings of both modules

#### Scenario: New shared module
- **WHEN** a shared module is added to the central repository
- **THEN** overlays can include it by its name after their next update

### Requirement: Default overlay is configurable
The flake URL that `nixos-central private setup` uses when none is given SHALL default to `git+ssh://git@github.com/tran-engineering/nixos-central-private`. A fork of the central repository SHALL be able to change it in one place, for NixOS machines and standalone homes alike.

#### Scenario: Fork changes the default
- **WHEN** a fork sets the default overlay to `git+ssh://git@github.com/acme/private`, and a user of that fork runs `nixos-central private setup`
- **THEN** `git+ssh://git@github.com/acme/private` is set up

### Requirement: Showing the overlay state
`nixos-central private` without an action SHALL print whether the local flake declares an overlay and, if so, its flake URL. It SHALL then print the usage of `setup` and `remove`, including the default overlay URL, and exit successfully. It MUST change nothing and MUST NOT need root.

#### Scenario: Overlay declared
- **WHEN** the machine's flake declares the overlay `git+ssh://git@github.com/alice/private` and a user runs `nixos-central private`
- **THEN** the command prints that URL and the usage, and exits with status 0

#### Scenario: No overlay
- **WHEN** the local flake declares no overlay and a user runs `nixos-central private`
- **THEN** the command says there is no private overlay, shows how to add one with `nixos-central private setup`, and exits with status 0

#### Scenario: Unknown action
- **WHEN** a user runs `nixos-central private frobnicate`
- **THEN** the command prints the usage, exits with an error and changes nothing
