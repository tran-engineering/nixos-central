# Spec Delta

## ADDED Requirements

### Requirement: Upgrading only the overlay on demand
`nixos-central-upgrade --private` SHALL update only the `private` input in `/etc/nixos` to its latest revision, activate the result in the running system and make it the default boot entry; `central` MUST stay at its locked revision. It MUST NOT reboot the machine, and it MUST refuse to start while the automatic upgrade is running, like `nixos-central-upgrade`.

#### Scenario: Overlay changed, central changed too
- **WHEN** both the central repository and the overlay have new commits and a user runs `nixos-central-upgrade --private`
- **THEN** `private` in `/etc/nixos/flake.lock` points to the new overlay revision, `central` is unchanged, and the overlay's changes are active and in the default boot entry

#### Scenario: No overlay declared
- **WHEN** the machine declares no private overlay and a user runs `nixos-central-upgrade --private`
- **THEN** the command fails with an error saying the machine has no private overlay, and the running system, the default boot entry and the lock file are unchanged

#### Scenario: Overlay unreachable
- **WHEN** the overlay cannot be fetched and a user runs `nixos-central-upgrade --private`
- **THEN** the command fails with an error, and the running system, the default boot entry and `/etc/nixos/flake.lock` are unchanged
