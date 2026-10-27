# Spec Delta

## MODIFIED Requirements

### Requirement: Daily automatic upgrade staged for next boot
Each machine SHALL check daily for a newer revision of the central repository, update its `central` input and, if declared, its `private` input, and build the result as the default boot entry without activating it in the running system. A run missed while the machine was off MUST run soon after the machine is next online.

#### Scenario: Update available
- **WHEN** the central repository has new commits and the daily upgrade runs
- **THEN** a new generation becomes the default boot entry while the running system stays unchanged

#### Scenario: Machine was off at scheduled time
- **WHEN** a laptop was powered off during the scheduled upgrade time
- **THEN** the upgrade runs shortly after the laptop is next booted

#### Scenario: Overlay updated
- **WHEN** a machine declares a private overlay that has new commits and the daily upgrade runs
- **THEN** the staged generation contains the new overlay revision

### Requirement: Upgrading immediately on demand
The system SHALL provide a command `nixos-central-upgrade` that updates the `central` input in `/etc/nixos`, and the `private` input if declared, to their latest revisions, activates the result in the running system, and makes it the default boot entry. It MUST update no other input and MUST NOT reboot the machine.

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
- **WHEN** the configuration fails to build, or the central repository or the private overlay cannot be fetched
- **THEN** the command fails with an error, and the running system, the default boot entry and `/etc/nixos/flake.lock` are unchanged
