# Spec Delta

## MODIFIED Requirements

### Requirement: Overlay is added after installation by one command
The system SHALL provide a subcommand `nixos-central private setup [<flake-url>] [--profile <name>]` that verifies the repository can be read with the user's SSH key, adds the overlay to the local flake (machine or standalone home), on a standalone home optionally records the profile name, and activates the result. It MUST change nothing if the repository can't be read.

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
- **WHEN** a user of a standalone home runs the setup command with `--profile kt`, and `kt` exists only in the overlay
- **THEN** the local flake records profile `kt`, the user gets the central default profile plus the overlay's `kt` profile, and no "profile does not exist" warning is shown

#### Scenario: Default overlay
- **WHEN** a user runs `nixos-central private setup` without a flake URL
- **THEN** the command says it uses the default overlay and sets up `git+ssh://git@github.com/tran-engineering/nixos-central-private`, as if that URL had been given

#### Scenario: Default overlay with a profile
- **WHEN** a user of a standalone home runs `nixos-central private setup --profile kt`
- **THEN** the default overlay is set up with profile `kt`

### Requirement: Overlay can be removed
`nixos-central private remove` SHALL remove the overlay from the local flake and activate the configuration without it.

#### Scenario: Remove
- **WHEN** a user runs `nixos-central private remove`
- **THEN** the local flake no longer declares the overlay and the overlay's files are gone after activation

## ADDED Requirements

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
