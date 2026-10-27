# Spec Delta

## ADDED Requirements

### Requirement: Showing what an update changes
The system SHALL provide a command `nixos-central-diff`, usable by any user without root, that lists the packages added, removed and changed in version between two system generations and changes nothing. While an update is staged, it MUST compare the running system with the staged generation; otherwise the newest generation with the one before it. The output MUST say which of the two it compares.

#### Scenario: Update staged
- **WHEN** the daily upgrade has staged a new generation and a user runs `nixos-central-diff`
- **THEN** the command lists the package changes from the running system to the staged generation and says they apply on the next reboot

#### Scenario: Update already in use
- **WHEN** the running system is the newest generation (after a reboot or `nixos-central-upgrade`) and a user runs `nixos-central-diff`
- **THEN** the command lists the package changes from the previous generation to the newest one, naming both generation numbers

#### Scenario: Branch being tried
- **WHEN** a branch activated with `nixos-central-try` is running and a user runs `nixos-central-diff`
- **THEN** the command lists the package changes from the tried configuration to the default boot entry, which a reboot returns to

#### Scenario: No previous generation
- **WHEN** the system has only one generation and nothing is staged, and a user runs `nixos-central-diff`
- **THEN** the command says there is no earlier generation to compare with and succeeds

#### Scenario: Unknown argument
- **WHEN** a user runs `nixos-central-diff` with any argument
- **THEN** the command prints its usage, exits with an error and changes nothing

## MODIFIED Requirements

### Requirement: Reboot-pending notification
When the default boot generation differs from the running system, the logged-in desktop user SHALL receive a desktop notification that an update is ready and will apply on reboot, and that `nixos-central-diff` shows what it changes. The notification MUST not repeat more than once per new generation per session.

#### Scenario: Update staged
- **WHEN** an automatic upgrade has staged a new generation
- **THEN** the desktop user sees "Update ready – reboot when convenient" once, with a body that mentions `nixos-central-diff`

#### Scenario: After reboot
- **WHEN** the user reboots into the staged generation
- **THEN** no reboot-pending notification is shown
