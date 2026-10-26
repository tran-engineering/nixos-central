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
