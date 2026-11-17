## ADDED Requirements

### Requirement: Upgrades as root can fetch the overlay
On NixOS machines, `nixos-central upgrade` SHALL fetch the overlay as root with the primary user's SSH key. GitHub's host keys SHALL be known in advance, so no host-key prompt can block a fetch.

#### Scenario: Upgrade with overlay
- **WHEN** the overlay repository has new commits and the primary user runs `nixos-central upgrade`
- **THEN** the activated generation contains the new overlay revision, and no host-key prompt is shown

## MODIFIED Requirements

### Requirement: Overlay failures stop updates instead of dropping the overlay
If a machine with an overlay can't fetch it, every upgrade MUST fail without changing the running system, the boot entries or the lock file. A configuration without the overlay MUST NOT be built in its place.

#### Scenario: Key revoked
- **WHEN** the SSH key is no longer accepted by GitHub and the user runs `nixos-central upgrade`
- **THEN** the upgrade fails with an error, the overlay's files stay in place, and the running system, the boot entries and the lock file are unchanged

## REMOVED Requirements

### Requirement: Unattended upgrades can fetch the overlay
**Reason**: There are no unattended upgrades any more; replaced by "Upgrades as root can fetch the overlay".
**Migration**: None.
