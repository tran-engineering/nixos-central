# Spec Delta

## ADDED Requirements

### Requirement: Base configuration for every user
The central repository SHALL provide one base home configuration that every primary user of a NixOS machine and every standalone home gets, with or without a private overlay. The base configuration is not a selectable profile. Its settings SHALL be defaults that a profile can override by setting the same option, without forcing.

#### Scenario: New user without overlay
- **WHEN** a machine is installed with user `alice` and no private overlay
- **THEN** the system installs successfully and `alice` gets the base configuration

#### Scenario: Overlay profile on top of the base
- **WHEN** `alice`'s machine declares an overlay whose `alice` profile adds a package
- **THEN** `alice` gets the base configuration plus the overlay profile's package

#### Scenario: Overlay overrides a base setting
- **WHEN** an overlay profile sets `EDITOR` to `nano` without forcing it, and the base configuration sets it to `vim`
- **THEN** the build succeeds and `alice`'s `EDITOR` is `nano`

### Requirement: Central repository holds no personal profiles
The central repository MUST NOT contain personal profiles. Profiles SHALL exist only in private overlays (see `private-overlay`). Profiles that exist only to test the central repository SHALL be kept with its tests and MUST NOT be selectable by machines or standalone homes.

#### Scenario: Recorded profile names a test profile
- **WHEN** a machine without an overlay records profile `ci-user`
- **THEN** the user gets the base configuration only, and the build warns that the recorded profile has no effect without an overlay

## RENAMED Requirements

- FROM: `### Requirement: Customization happens in the central repository`
- TO: `### Requirement: Customization happens in the private overlay`

## MODIFIED Requirements

### Requirement: Profiles are resolved at build time
The profile SHALL be chosen each time the system or home is built, so a profile added to the private overlay later takes effect on the next update without changing the machine or home.

#### Scenario: Profile added later
- **WHEN** `alice`'s profile is added to her private overlay after her machine was installed with the overlay's default profile
- **THEN** her machine uses the overlay's `alice` profile after its next update that includes the overlay, with no edit to `/etc/nixos`

### Requirement: Customization happens in the private overlay
Persistent customization of a user's environment SHALL be done in the user's private overlay (see `private-overlay`). Changes in the central repository (base configuration, shared modules) affect every user. Apart from declaring that one overlay and its profile, neither the machine-local flake nor the local flake of a standalone home MUST provide a user-level customization layer.

#### Scenario: User wants a permanent new package
- **WHEN** a user wants a package available permanently
- **THEN** the documented path is a change to their profile in their private overlay, which reaches the machine via updates

#### Scenario: Standalone home wants a new package
- **WHEN** a user of a standalone home wants a package available permanently
- **THEN** the documented path is a change to their profile in their private overlay, not an edit to `~/.config/home-manager`

#### Scenario: Private file
- **WHEN** a user wants a file on their machines that must not be public, such as a work SSH configuration
- **THEN** the documented path is their private overlay

#### Scenario: Change for every user
- **WHEN** a package should be available to every user of every machine
- **THEN** the documented path is a change to the base configuration in the central repository

### Requirement: Profiles can use packages from nixpkgs-unstable
Overlay profiles, the base configuration, shared modules and NixOS modules in the central repository SHALL be able to refer to packages of the locked nixpkgs-unstable input as `pkgs.unstable.<name>`, with the same package configuration (e.g. unfree allowed) as the stable packages. Packages that are not referred to this way MUST come from the stable nixpkgs.

#### Scenario: Newer package in a profile
- **WHEN** `alice`'s overlay profile adds `pkgs.unstable.helix` to her packages
- **THEN** after the next update `alice` has `helix` at the version of the locked nixpkgs-unstable revision

#### Scenario: Unfree package from unstable
- **WHEN** a profile adds an unfree package via `pkgs.unstable`
- **THEN** the system builds without additional configuration

#### Scenario: Ad-hoc shells unaffected
- **WHEN** a user runs `nix-shell -p hello`
- **THEN** `hello` comes from the system's stable nixpkgs, not from unstable

### Requirement: Profiles work on NixOS and standalone
The base configuration and the central repository's test profiles SHALL build both as the primary user's environment on a NixOS machine and as a standalone home on another Linux distribution. Neither the base configuration nor a shared module MUST depend on options that exist only on NixOS without guarding them.

#### Scenario: Same profile on both
- **WHEN** the base configuration is used by NixOS machine `foo` and by a standalone home on Ubuntu, both without an overlay
- **THEN** both build, and both contain the programs and settings of the base configuration

#### Scenario: Default profile standalone
- **WHEN** a standalone home has no overlay
- **THEN** it builds and activates with the base configuration

### Requirement: Standalone homes choose their profile
A standalone home SHALL use the overlay profile named by the profile recorded in its local flake, or by the login name if none is recorded (see `private-overlay`). The choice is resolved each time the home is built. Without an overlay, a recorded profile SHALL have no effect; the build MUST warn about it, except for the value `_default` written by earlier home installers.

#### Scenario: Profile differs from login name
- **WHEN** the standalone home of `khoi.tran` declares an overlay and records profile `kt`
- **THEN** `khoi.tran`'s environment is built from the base configuration plus the overlay's `kt` profile

#### Scenario: Recorded profile removed later
- **WHEN** the profile recorded in a standalone home is removed from its overlay, and the overlay has a default profile
- **THEN** the home's next build uses the base configuration plus the overlay's default profile and warns that the recorded profile no longer exists in the overlay

#### Scenario: Profile exists only in the private overlay
- **WHEN** a standalone home records profile `kt` and the home's private overlay has a `kt` profile
- **THEN** the home is built from the base configuration plus the overlay's `kt` profile, without a warning

#### Scenario: Recorded profile without overlay
- **WHEN** a standalone home records profile `kt` and declares no overlay
- **THEN** the home builds with the base configuration and warns that the recorded profile has no effect without an overlay

#### Scenario: Home from an earlier installer
- **WHEN** a standalone home records profile `_default` and declares no overlay
- **THEN** the home builds with the base configuration without a warning

### Requirement: NixOS machines can record a profile
A NixOS machine flake SHALL be able to record a profile name. If one is recorded, it SHALL be used in place of the primary user's name to choose the overlay profile. Without a recorded profile, the primary user's name SHALL be used. Without an overlay, a recorded profile SHALL have no effect and the build MUST warn about it. The account name MUST stay the primary user's name either way.

#### Scenario: Profile that exists only in the overlay
- **WHEN** machine `foo` has primary user `alice`, records profile `developer`, and the overlay has a profile `developer`
- **THEN** `alice`'s environment is built from the base configuration plus the overlay's `developer` profile, and her login name and home directory stay `alice`

#### Scenario: Recorded profile exists in the central repository
- **WHEN** machine `foo` records profile `ci-user`, the name of one of the central repository's test profiles, and declares an overlay that has a default profile but no `ci-user` profile
- **THEN** the primary user gets the base configuration plus the overlay's default profile, the central test profile is not used, and the build warns that the overlay has no profile `ci-user`

#### Scenario: Recorded profile without overlay
- **WHEN** machine `foo` records profile `kt` and declares no overlay
- **THEN** the primary user gets the base configuration and the build warns that the recorded profile has no effect without an overlay

#### Scenario: No recorded profile
- **WHEN** a machine flake declares an overlay and records no profile
- **THEN** the overlay profile is chosen by the primary user's name

## REMOVED Requirements

### Requirement: Personal profile overrides the default
**Reason**: The central repository no longer holds personal profiles. Personal configuration lives in private overlays, which always add to the base configuration.
**Migration**: Move the personal profile to `homeModules.<name>` of a private overlay and set it up with `nixos-central private setup --profile <name>`. Settings that the profile overrode with `mkForce` can be set plainly, because the base configuration only sets defaults.

### Requirement: Fallback to the shared default profile
**Reason**: Replaced by "Base configuration for every user": the former default profile is now the base that every user gets, so there is nothing to fall back from.
**Migration**: None. Users who had the default profile get the same settings from the base configuration.

### Requirement: Selectable profile list
**Reason**: Without central profiles there is nothing to select in the central repository. Installers list the overlay's profiles instead.
**Migration**: Use the overlay's `homeModules` names. `lib.profileNames` is removed.
