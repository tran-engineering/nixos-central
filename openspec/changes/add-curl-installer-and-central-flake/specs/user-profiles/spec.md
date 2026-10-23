# Spec Delta

## Purpose

Defines how a machine's primary user gets an account and a personal environment from the central repository, falling back to a shared default profile until a personal one exists.

## ADDED Requirements

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
Persistent customization of a user's environment SHALL be done only by changing the user's profile in the central repository. The machine-local flake MUST NOT provide a user-level customization layer.

#### Scenario: User wants a permanent new package
- **WHEN** a user wants a package available permanently
- **THEN** the documented path is a change to their profile in the central repository, which reaches the machine via updates
