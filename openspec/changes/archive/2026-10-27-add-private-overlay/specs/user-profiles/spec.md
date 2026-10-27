# Spec Delta

## MODIFIED Requirements

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

