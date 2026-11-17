## MODIFIED Requirements

### Requirement: Installed system has the overlay and the key
When an overlay was set up, the installed system SHALL be built with the overlay declared in its machine flake, in the same form that `nixos-central private setup` writes, so that `nixos-central private remove` works on it. The generated key SHALL be installed as the primary user's `~/.ssh/id_ed25519` and `~/.ssh/id_ed25519.pub`, owned by that user, with the private key readable only by them.

#### Scenario: First boot with overlay
- **WHEN** the machine installed with an overlay boots and the primary user logs in
- **THEN** the overlay's files are present, and `nixos-central upgrade` can fetch the overlay with the installed key

#### Scenario: Remove after install
- **WHEN** the primary user runs `nixos-central private remove` on a machine installed with an overlay and profile
- **THEN** the overlay and the recorded profile are removed from the machine flake and the system activates without them
