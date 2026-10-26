# Spec Delta

## ADDED Requirements

### Requirement: Profiles work on NixOS and standalone
Every profile in the central repository, including the shared default profile, SHALL build both as the primary user's environment on a NixOS machine and as a standalone home on another Linux distribution. A profile MUST NOT depend on options that exist only on NixOS without guarding them.

#### Scenario: Same profile on both
- **WHEN** profile `kt` is used by NixOS machine `foo` and by a standalone home on Ubuntu
- **THEN** both build, and both contain the programs and settings from `kt`

#### Scenario: Default profile standalone
- **WHEN** a standalone home uses the shared default profile
- **THEN** it builds and activates

### Requirement: Standalone homes choose their profile
A standalone home SHALL use the profile recorded in its local flake, independent of the login name. If no profile is recorded, the profile named like the login name SHALL be used, and the shared default profile if none exists. The choice is resolved each time the home is built.

#### Scenario: Profile differs from login name
- **WHEN** the standalone home of `khoi.tran` records profile `kt`
- **THEN** `khoi.tran`'s environment is built from `kt`

#### Scenario: Recorded profile removed later
- **WHEN** the profile recorded in a standalone home is removed from the central repository
- **THEN** the home's next build uses the shared default profile and warns that the recorded profile no longer exists

### Requirement: Selectable profile list
The central repository SHALL expose the names of the profiles a user can select: every personal profile plus the shared default profile, excluding profiles that exist only for testing.

#### Scenario: Test profile hidden
- **WHEN** the repository contains `users/_default`, `users/kt` and the CI test profile
- **THEN** the selectable profiles are the default profile and `kt`

## MODIFIED Requirements

### Requirement: Customization happens in the central repository
Persistent customization of a user's environment SHALL be done only by changing the user's profile in the central repository. Neither the machine-local flake nor the local flake of a standalone home MUST provide a user-level customization layer.

#### Scenario: User wants a permanent new package
- **WHEN** a user wants a package available permanently
- **THEN** the documented path is a change to their profile in the central repository, which reaches the machine via updates

#### Scenario: Standalone home wants a new package
- **WHEN** a user of a standalone home wants a package available permanently
- **THEN** the documented path is a change to their profile in the central repository, not an edit to `~/.config/home-manager`
