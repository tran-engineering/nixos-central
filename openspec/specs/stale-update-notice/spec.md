# stale-update-notice Specification

## Purpose

Reminds a user in a new terminal how long ago their machine or standalone home was last updated, and shows the command to update, once that is more than a threshold ago; recently updated machines show nothing.

## Requirements

### Requirement: Notice when updates stopped
When the user starts an interactive bash, fish or zsh shell and the last successful update is older than the threshold, the shell SHALL print a notice. While the last successful update is within the threshold, nothing MUST be printed, however old the running system or the central revision are. This applies to every profile, on NixOS machines and standalone homes.

#### Scenario: Updates failing for a while
- **WHEN** the last successful update was 9 days ago, the threshold is 1 day, and the user opens a terminal
- **THEN** the shell prints a notice saying the last successful update was 9 days ago

#### Scenario: Updating normally, quiet repository
- **WHEN** the user ran `nixos-central upgrade` 3 hours ago, but the central repository has had no commits for 12 days
- **THEN** opening a terminal prints no notice

#### Scenario: Profile without shared shell modules
- **WHEN** a user with the shared default profile opens a bash terminal while updates are stale
- **THEN** the notice is printed

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

### Requirement: Ages in the notice
The notice SHALL state, in whole days, how long ago the last successful update was, how old the running configuration is, and how old the pinned central revision is. The running configuration's age is the time since it was installed as a generation (NixOS system generation, or active home-manager generation on a standalone home). The central revision's age is the time since the commit date of `central` in the machine's or home's flake lock file.

#### Scenario: All ages known
- **WHEN** the notice is printed, the last successful update was 9 days ago, the running system generation was installed 15 days ago and the pinned central revision was committed 16 days ago
- **THEN** the notice states 9, 15 and 16 days respectively

#### Scenario: Update staged but not rebooted
- **WHEN** a new generation was made the default boot entry without activating it, but the running system was installed 10 days ago
- **THEN** the running system's age is reported as 10 days

### Requirement: Actionable hint
The notice SHALL show the command that installs the latest update, `nixos-central upgrade`, on NixOS machines and standalone homes. If a newer system generation is already staged, it SHALL additionally say to reboot to use it. The notice MUST NOT refer to an automatic or daily update.

#### Scenario: Nothing staged on NixOS
- **WHEN** the notice is printed on a NixOS machine and no newer generation is staged
- **THEN** the notice shows `nixos-central upgrade` as the command to update

#### Scenario: Staged update waiting
- **WHEN** the notice is printed and a newer generation is the default boot entry
- **THEN** the notice tells the user to reboot to use it, and also shows `nixos-central upgrade`

#### Scenario: Standalone home
- **WHEN** the notice is printed on a standalone home
- **THEN** the notice shows `nixos-central upgrade` as the command to update, and does not mention `home-manager-auto-upgrade`

### Requirement: Threshold set by the profile
The threshold SHALL default to 1 day. A profile SHALL be able to change it, or turn the notice off entirely.

#### Scenario: Default threshold
- **WHEN** the profile does not set a threshold and the last successful update was 2 days ago
- **THEN** a new terminal prints the notice

#### Scenario: Within the default threshold
- **WHEN** the profile does not set a threshold and the last successful update was 20 hours ago
- **THEN** a new terminal prints no notice

#### Scenario: Longer threshold
- **WHEN** profile `kt` sets the threshold to 14 days and the last successful update was 10 days ago
- **THEN** `kt` sees no notice

#### Scenario: Turned off
- **WHEN** a profile turns the notice off
- **THEN** no notice is printed regardless of the ages

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

### Requirement: Never disturbs the shell
Determining the ages MUST NOT make the shell fail to start, print errors, or noticeably delay it. An age that cannot be determined SHALL be left out of the notice; if the last successful update cannot be determined, nothing is printed. Non-interactive shells MUST NOT print the notice.

#### Scenario: Tried branch running
- **WHEN** a branch activated with `nixos-central try` is running and updates are stale
- **THEN** the shell starts normally and the notice leaves out the running system's age

#### Scenario: Lock file missing
- **WHEN** the flake lock file cannot be read
- **THEN** the shell starts normally without error output

#### Scenario: Script runs a command
- **WHEN** a non-interactive shell runs a command, e.g. `ssh foo uptime` or `bash -c ...`
- **THEN** the output contains no notice
