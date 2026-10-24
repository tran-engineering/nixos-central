# system-updates Specification

## Purpose

Keeps every installed machine in sync with the central repository automatically and safely, and lets users try unmerged changes without risking their system.

## Requirements

### Requirement: Daily automatic upgrade staged for next boot
Each machine SHALL check daily for a newer revision of the central repository, update its `central` input, and build the result as the default boot entry without activating it in the running system. A run missed while the machine was off MUST run soon after the machine is next online.

#### Scenario: Update available
- **WHEN** the central repository has new commits and the daily upgrade runs
- **THEN** a new generation becomes the default boot entry while the running system stays unchanged

#### Scenario: Machine was off at scheduled time
- **WHEN** a laptop was powered off during the scheduled upgrade time
- **THEN** the upgrade runs shortly after the laptop is next booted

### Requirement: No automatic reboot
The automatic upgrade MUST NOT reboot the machine.

#### Scenario: Kernel changed
- **WHEN** an upgrade includes a new kernel
- **THEN** the machine is not rebooted automatically

### Requirement: Reboot-pending notification
When the default boot generation differs from the running system, the logged-in desktop user SHALL receive a desktop notification that an update is ready and will apply on reboot. The notification MUST not repeat more than once per new generation per session.

#### Scenario: Update staged
- **WHEN** an automatic upgrade has staged a new generation
- **THEN** the desktop user sees "Update ready – reboot when convenient" once

#### Scenario: After reboot
- **WHEN** the user reboots into the staged generation
- **THEN** no reboot-pending notification is shown

### Requirement: Rollback via boot menu
Previous system generations SHALL remain selectable in the boot menu so a user can boot the last working generation if an update is broken.

#### Scenario: Broken update
- **WHEN** the newly staged generation fails to start the desktop
- **THEN** the user can select the previous generation in the boot menu and boot normally

### Requirement: Trying an unmerged branch
The system SHALL provide a command `nixos-central-try <branch>` that activates the machine's configuration built against the given branch of the central repository in the running system only, without creating a boot entry or changing `/etc/nixos`.

#### Scenario: Try a branch
- **WHEN** a user runs `nixos-central-try alice-wip`
- **THEN** the system activates the configuration from branch `alice-wip`, and `/etc/nixos/flake.lock` is unchanged

#### Scenario: Revert by reboot
- **WHEN** the user reboots after trying a branch
- **THEN** the system boots the regular default generation

#### Scenario: Branch does not exist
- **WHEN** the user runs `nixos-central-try no-such-branch`
- **THEN** the command fails with an error and the running system is unchanged

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
