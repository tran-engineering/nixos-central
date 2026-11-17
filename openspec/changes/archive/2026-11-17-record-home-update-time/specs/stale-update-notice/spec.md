# Spec Delta

## MODIFIED Requirements

### Requirement: Last successful update
The last successful update SHALL be the later of: the most recent successful completion of `nixos-central upgrade` (with or without `--private`, on NixOS or a standalone home), whether or not it changed anything; and the time the newest generation was installed (which also covers manual rebuilds and the installation). On a standalone home, a successful `nixos-central upgrade` MUST record its completion time in the stamp file as an ISO 8601 timestamp with its UTC offset, and set the file's modification time to the same moment. When the stamp file holds no readable timestamp, its modification time is the completion time.

#### Scenario: Upgrade without changes
- **WHEN** the user runs `nixos-central upgrade` successfully but it produces the same system or home as before
- **THEN** it counts as the last successful update

#### Scenario: Upgrade without changes on a standalone home
- **WHEN** the user of a standalone home runs `nixos-central upgrade` successfully and no new home generation is created
- **THEN** it counts as the last successful update, and the stamp file holds its completion time

#### Scenario: Failed upgrade
- **WHEN** `nixos-central upgrade` fails, e.g. because the machine is offline or the build fails
- **THEN** the last successful update stays at the previous successful run

#### Scenario: Manual switch on a standalone home
- **WHEN** the last `nixos-central upgrade` was 10 days ago, and the user ran `home-manager switch` with a changed configuration today
- **THEN** the last successful update is today

#### Scenario: No upgrade recorded yet
- **WHEN** a machine was installed 3 days ago and no upgrade has completed since
- **THEN** the last successful update is 3 days ago

#### Scenario: Stamp file without a timestamp
- **WHEN** a standalone home's stamp file was written by an earlier version and its content is not a timestamp
- **THEN** the last successful update is the file's modification time

### Requirement: Shown on demand
The notice SHALL also be available as the subcommand `nixos-central status`. Run by hand, it MUST print the notice with the ages and hint regardless of the threshold, also when the notice is turned off; a last successful update that cannot be determined is shown as unknown. Shells print it only when stale (`nixos-central status --if-stale`). On a standalone home, the notice MUST also state the date and time of the last successful update, in local time, next to its age; when that time cannot be determined, the date is left out.

#### Scenario: Recent update
- **WHEN** the last successful update was yesterday and the user runs `nixos-central status`
- **THEN** it prints that the last successful update was 1 day ago, with the other ages and the hint

#### Scenario: Standalone home shows the time
- **WHEN** a standalone home's last successful update was on 2026-11-16 at 08:04 local time and the user runs `nixos-central status` on 2026-11-17
- **THEN** the notice says the last successful update was on 2026-11-16 at 08:04 (1 day ago)

#### Scenario: Notice turned off
- **WHEN** the profile turns the notice off and the user runs `nixos-central status`
- **THEN** the notice is printed

#### Scenario: Unknown argument
- **WHEN** the user runs `nixos-central status` with an argument other than `--if-stale`
- **THEN** the command prints its usage, exits with an error and changes nothing
