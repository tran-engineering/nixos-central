# Spec Delta

## ADDED Requirements

### Requirement: Upgrading immediately on demand
The system SHALL provide a command `nixos-central-upgrade` that updates the `central` input in `/etc/nixos` to the latest revision of the central repository, activates the result in the running system, and makes it the default boot entry. It MUST update no input other than `central` and MUST NOT reboot the machine.

#### Scenario: Update available
- **WHEN** the central repository has new commits and a user runs `nixos-central-upgrade`
- **THEN** the new configuration is active in the running system, it is the default boot entry, and `central` in `/etc/nixos/flake.lock` points to the new revision

#### Scenario: Already up to date
- **WHEN** a user runs `nixos-central-upgrade` and `central` is already at the latest revision
- **THEN** the command succeeds and the running system and default boot entry are the current configuration

#### Scenario: Persists across reboot
- **WHEN** the user reboots after `nixos-central-upgrade`
- **THEN** the machine boots the configuration activated by the command

#### Scenario: Ends a tried branch
- **WHEN** a user runs `nixos-central-upgrade` while a branch activated with `nixos-central-try` is running
- **THEN** the running system is replaced by the configuration from the central repository's default branch

#### Scenario: No reboot-pending notification afterwards
- **WHEN** `nixos-central-upgrade` has completed and no newer generation has been staged since
- **THEN** the desktop user does not get the reboot-pending notification

#### Scenario: Kernel changed
- **WHEN** the configuration activated by `nixos-central-upgrade` has a different kernel than the booted system
- **THEN** the command does not reboot and tells the user that the new kernel is used after the next reboot

#### Scenario: Build fails
- **WHEN** the configuration fails to build or the central repository cannot be fetched
- **THEN** the command fails with an error, and the running system, the default boot entry and `/etc/nixos/flake.lock` are unchanged

### Requirement: No concurrent upgrades
`nixos-central-upgrade` MUST refuse to start while the automatic upgrade is running, with an error that says so, and MUST change nothing in that case.

#### Scenario: Automatic upgrade in progress
- **WHEN** a user runs `nixos-central-upgrade` while the daily automatic upgrade is running
- **THEN** the command exits with an error explaining that an upgrade is already in progress, and the system is unchanged
