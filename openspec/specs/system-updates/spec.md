# system-updates Specification

## Purpose

Lets users update every installed machine to the central repository safely, when they choose to, and try unmerged changes without risking their system.

## Requirements

### Requirement: Reboot-pending notification
When the default boot generation differs from the running system, the logged-in desktop user SHALL receive a desktop notification that an update is ready and will apply on reboot, and that `nixos-central diff` shows what it changes. The notification MUST not repeat more than once per new generation per session.

#### Scenario: Update staged
- **WHEN** a new generation has been made the default boot entry without activating it, e.g. with `nixos-rebuild boot`
- **THEN** the desktop user sees "Update ready – reboot when convenient" once, with a body that mentions `nixos-central diff`

#### Scenario: After reboot
- **WHEN** the user reboots into the staged generation
- **THEN** no reboot-pending notification is shown

### Requirement: Rollback via boot menu
Previous system generations SHALL remain selectable in the boot menu so a user can boot the last working generation if an update is broken.

#### Scenario: Broken update
- **WHEN** the newly staged generation fails to start the desktop
- **THEN** the user can select the previous generation in the boot menu and boot normally

### Requirement: Trying an unmerged branch
The system SHALL provide a subcommand `nixos-central try <branch>` that activates the machine's configuration built against the given branch of the central repository in the running system only, without creating a boot entry or changing `/etc/nixos`.

#### Scenario: Try a branch
- **WHEN** a user runs `nixos-central try alice-wip`
- **THEN** the system activates the configuration from branch `alice-wip`, and `/etc/nixos/flake.lock` is unchanged

#### Scenario: Revert by reboot
- **WHEN** the user reboots after trying a branch
- **THEN** the system boots the regular default generation

#### Scenario: Branch does not exist
- **WHEN** the user runs `nixos-central try no-such-branch`
- **THEN** the command fails with an error and the running system is unchanged

#### Scenario: No branch given
- **WHEN** the user runs `nixos-central try` without a branch
- **THEN** the command prints its usage, exits with an error and changes nothing

### Requirement: Upgrading immediately on demand
The system SHALL provide a subcommand `nixos-central upgrade` that updates the `central` input in `/etc/nixos`, and the `private` input if declared, to their latest revisions, activates the result in the running system, and makes it the default boot entry. It MUST update no other input and MUST NOT reboot the machine. It is the only way a machine is updated to newer revisions of the central repository.

#### Scenario: Update available
- **WHEN** the central repository has new commits and a user runs `nixos-central upgrade`
- **THEN** the new configuration is active in the running system, it is the default boot entry, and `central` in `/etc/nixos/flake.lock` points to the new revision

#### Scenario: Already up to date
- **WHEN** a user runs `nixos-central upgrade` and `central` is already at the latest revision
- **THEN** the command succeeds and the running system and default boot entry are the current configuration

#### Scenario: Persists across reboot
- **WHEN** the user reboots after `nixos-central upgrade`
- **THEN** the machine boots the configuration activated by the command

#### Scenario: Ends a tried branch
- **WHEN** a user runs `nixos-central upgrade` while a branch activated with `nixos-central try` is running
- **THEN** the running system is replaced by the configuration from the central repository's default branch

#### Scenario: No reboot-pending notification afterwards
- **WHEN** `nixos-central upgrade` has completed and no newer generation has been staged since
- **THEN** the desktop user does not get the reboot-pending notification

#### Scenario: Kernel changed
- **WHEN** the configuration activated by `nixos-central upgrade` has a different kernel than the booted system
- **THEN** the command does not reboot and tells the user that the new kernel is used after the next reboot

#### Scenario: Build fails
- **WHEN** the configuration fails to build, or the central repository or the private overlay cannot be fetched
- **THEN** the command fails with an error, and the running system, the default boot entry and `/etc/nixos/flake.lock` are unchanged

### Requirement: Upgrading only the overlay on demand
`nixos-central upgrade --private` SHALL update only the `private` input in `/etc/nixos` to its latest revision, activate the result in the running system and make it the default boot entry; `central` MUST stay at its locked revision. It MUST NOT reboot the machine.

#### Scenario: Overlay changed, central changed too
- **WHEN** both the central repository and the overlay have new commits and a user runs `nixos-central upgrade --private`
- **THEN** `private` in `/etc/nixos/flake.lock` points to the new overlay revision, `central` is unchanged, and the overlay's changes are active and in the default boot entry

#### Scenario: No overlay declared
- **WHEN** the machine declares no private overlay and a user runs `nixos-central upgrade --private`
- **THEN** the command fails with an error saying the machine has no private overlay and naming `nixos-central private setup`, and the running system, the default boot entry and the lock file are unchanged

#### Scenario: Overlay unreachable
- **WHEN** the overlay cannot be fetched and a user runs `nixos-central upgrade --private`
- **THEN** the command fails with an error, and the running system, the default boot entry and `/etc/nixos/flake.lock` are unchanged

### Requirement: Showing what an update changes
The system SHALL provide a subcommand `nixos-central diff`, usable by any user without root, that lists the packages added, removed and changed in version between two system generations and changes nothing. While an update is staged, it MUST compare the running system with the staged generation; otherwise the newest generation with the one before it. The output MUST say which of the two it compares.

#### Scenario: Update staged
- **WHEN** a new generation is the default boot entry but not running (e.g. after `nixos-rebuild boot`) and a user runs `nixos-central diff`
- **THEN** the command lists the package changes from the running system to the staged generation and says they apply on the next reboot

#### Scenario: Update already in use
- **WHEN** the running system is the newest generation (after a reboot or `nixos-central upgrade`) and a user runs `nixos-central diff`
- **THEN** the command lists the package changes from the previous generation to the newest one, naming both generation numbers

#### Scenario: Branch being tried
- **WHEN** a branch activated with `nixos-central try` is running and a user runs `nixos-central diff`
- **THEN** the command lists the package changes from the tried configuration to the default boot entry, which a reboot returns to

#### Scenario: No previous generation
- **WHEN** the system has only one generation and nothing is staged, and a user runs `nixos-central diff`
- **THEN** the command says there is no earlier generation to compare with and succeeds

#### Scenario: Unknown argument
- **WHEN** a user runs `nixos-central diff` with any argument
- **THEN** the command prints its usage, exits with an error and changes nothing

### Requirement: Upgrade reports driver changes that need a reboot
When `nixos-central upgrade` activates a configuration whose kernel is unchanged but whose kernel modules differ from the booted system's, such as a new NVIDIA driver, it SHALL tell the user that the new drivers are used after the next reboot and that programs using the GPU may fail until then. It MUST NOT reboot the machine.

#### Scenario: NVIDIA driver changed
- **WHEN** `nixos-central upgrade` activates a configuration with a new NVIDIA driver and the same kernel as the booted system
- **THEN** the command does not reboot and tells the user that the new drivers are used after the next reboot

#### Scenario: Kernel modules unchanged
- **WHEN** `nixos-central upgrade` activates a configuration with the same kernel and kernel modules as the booted system
- **THEN** the command prints no reboot hint

### Requirement: No automatic upgrades
A NixOS machine MUST NOT update its flake inputs, build a new system or stage a new boot entry on its own. The `central` and `private` inputs in `/etc/nixos/flake.lock` SHALL change only when a user runs `nixos-central upgrade` or edits the flake. The machine MUST NOT reboot itself to apply an update.

#### Scenario: New commits in the central repository
- **WHEN** the central repository has new commits and the machine stays on for several days without anyone running `nixos-central upgrade`
- **THEN** `/etc/nixos/flake.lock`, the running system and the default boot entry are unchanged

#### Scenario: No upgrade timer
- **WHEN** a user lists the machine's systemd timers
- **THEN** there is no timer that upgrades the system
