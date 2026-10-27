# user-profiles Specification

## Purpose

Defines how a machine's primary user gets an account and a personal environment from the central repository, falling back to a shared default profile until a personal one exists.

## Requirements

### Requirement: Primary user account
Each machine SHALL have one primary user, named by the machine flake, as a normal account with administrative rights (sudo) and the password hash set at install time.

#### Scenario: Login and sudo
- **WHEN** the primary user logs in after installation
- **THEN** login succeeds with the install-time password and `sudo` works for that user

### Requirement: Personal profile overrides the default
If the central repository contains a profile for the primary user's name, the machine SHALL use it in place of the shared default profile. A personal profile MAY reuse the default profile explicitly; it MUST NOT be merged with the default implicitly.

#### Scenario: Personal profile exists
- **WHEN** the central repository contains a profile for `bob` and machine `foo` has primary user `bob`
- **THEN** `bob`'s environment on `foo` is built from `bob`'s profile

#### Scenario: Personal profile reuses the default
- **WHEN** `bob`'s profile explicitly includes the default profile and overrides one setting
- **THEN** `bob` gets everything from the default except the overridden setting

### Requirement: Fallback to the shared default profile
If no profile for the primary user's name exists in the central repository, the machine SHALL use the shared default profile.

#### Scenario: New user without profile
- **WHEN** a machine is installed with user `alice` and the repository has no `alice` profile
- **THEN** the system installs successfully and `alice` gets the default profile

### Requirement: Profiles are resolved at build time
The choice between personal and default profile SHALL be made each time the system is built, so adding a personal profile to the repository takes effect on the next update without changing the machine.

#### Scenario: Profile added later
- **WHEN** `alice`'s profile is merged into the central repository after her machine was installed
- **THEN** her machine uses `alice`'s profile after its next update, with no edit to `/etc/nixos`

### Requirement: Customization happens in the central repository
Persistent customization of a user's environment SHALL be done by changing the user's profile in the central repository, or in the user's private overlay (see `private-overlay`). Apart from declaring that one overlay, neither the machine-local flake nor the local flake of a standalone home MUST provide a user-level customization layer.

#### Scenario: User wants a permanent new package
- **WHEN** a user wants a package available permanently
- **THEN** the documented path is a change to their profile in the central repository, which reaches the machine via updates

#### Scenario: Standalone home wants a new package
- **WHEN** a user of a standalone home wants a package available permanently
- **THEN** the documented path is a change to their profile in the central repository, not an edit to `~/.config/home-manager`

#### Scenario: Private file
- **WHEN** a user wants a file on their machines that must not be public, such as a work SSH configuration
- **THEN** the documented path is their private overlay

### Requirement: Profiles can use packages from nixpkgs-unstable
User profiles and NixOS modules in the central repository SHALL be able to refer to packages of the locked nixpkgs-unstable input as `pkgs.unstable.<name>`, with the same package configuration (e.g. unfree allowed) as the stable packages. Packages that are not referred to this way MUST come from the stable nixpkgs.

#### Scenario: Newer package in a profile
- **WHEN** `alice`'s profile adds `pkgs.unstable.helix` to her packages
- **THEN** after the next update `alice` has `helix` at the version of the locked nixpkgs-unstable revision

#### Scenario: Unfree package from unstable
- **WHEN** a profile adds an unfree package via `pkgs.unstable`
- **THEN** the system builds without additional configuration

#### Scenario: Ad-hoc shells unaffected
- **WHEN** a user runs `nix-shell -p hello`
- **THEN** `hello` comes from the system's stable nixpkgs, not from unstable

### Requirement: Profiles work on NixOS and standalone
Every profile in the central repository, including the shared default profile, SHALL build both as the primary user's environment on a NixOS machine and as a standalone home on another Linux distribution. A profile MUST NOT depend on options that exist only on NixOS without guarding them.

#### Scenario: Same profile on both
- **WHEN** profile `kt` is used by NixOS machine `foo` and by a standalone home on Ubuntu
- **THEN** both build, and both contain the programs and settings from `kt`

#### Scenario: Default profile standalone
- **WHEN** a standalone home uses the shared default profile
- **THEN** it builds and activates

### Requirement: Standalone homes choose their profile
A standalone home SHALL use the profile recorded in its local flake, independent of the login name. If no profile is recorded, the profile named like the login name SHALL be used, and the shared default profile if none exists. The same name selects the profile of the home's private overlay (see `private-overlay`). The choice is resolved each time the home is built.

#### Scenario: Profile differs from login name
- **WHEN** the standalone home of `khoi.tran` records profile `kt`
- **THEN** `khoi.tran`'s environment is built from `kt`

#### Scenario: Recorded profile removed later
- **WHEN** the profile recorded in a standalone home is removed from the central repository
- **THEN** the home's next build uses the shared default profile and warns that the recorded profile no longer exists

#### Scenario: Profile exists only in the private overlay
- **WHEN** a standalone home records profile `kt`, the central repository has no `kt` profile, and the home's private overlay has one
- **THEN** the home is built from the shared default profile plus the overlay's `kt` profile, without a warning

### Requirement: Selectable profile list
The central repository SHALL expose the names of the profiles a user can select: every personal profile plus the shared default profile, excluding profiles that exist only for testing.

#### Scenario: Test profile hidden
- **WHEN** the repository contains `users/_default`, `users/kt` and the CI test profile
- **THEN** the selectable profiles are the default profile and `kt`

### Requirement: Profile selects the login shell
A profile SHALL be able to select the user's login shell among bash, fish and zsh; bash is the default. The selected shell MUST be usable without further configuration in the profile. On a NixOS machine, the primary user's login shell SHALL be the selected shell.

#### Scenario: Profile selects fish on NixOS
- **WHEN** `kt`'s profile selects fish and machine `foo` has primary user `kt`
- **THEN** after the next update and a new login, `kt`'s login shell on `foo` is fish

#### Scenario: No selection
- **WHEN** a profile does not select a shell
- **THEN** the user's login shell is bash

#### Scenario: Shell selected without its module
- **WHEN** a profile selects zsh but does not include the shared `zsh` module
- **THEN** the build succeeds and zsh is installed and works as the login shell

#### Scenario: Standalone home
- **WHEN** a standalone home's profile selects fish
- **THEN** fish is installed and configured, and the login shell is left unchanged (see `home-installer`)
