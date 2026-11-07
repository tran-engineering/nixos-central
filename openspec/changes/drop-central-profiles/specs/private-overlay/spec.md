# Spec Delta

## RENAMED Requirements

- FROM: `### Requirement: Overlay profile is chosen like a central profile`
- TO: `### Requirement: Overlay profile is chosen by the recorded profile or the user's name`

## MODIFIED Requirements

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
