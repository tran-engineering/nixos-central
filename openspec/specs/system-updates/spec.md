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
