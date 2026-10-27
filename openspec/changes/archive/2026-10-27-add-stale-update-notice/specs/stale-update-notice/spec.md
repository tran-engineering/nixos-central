# Spec Delta

## Purpose

Tells a user in a new terminal when their machine or standalone home has not managed to update for a while, so silently stopped updates get noticed, while machines that update normally show nothing.

## ADDED Requirements

### Requirement: Notice when updates stopped
When the user starts an interactive bash, fish or zsh shell and the last successful update is older than the threshold, the shell SHALL print a notice. While the last successful update is within the threshold, nothing MUST be printed, however old the running system or the central revision are. This applies to every profile, on NixOS machines and standalone homes.

#### Scenario: Updates failing for a while
- **WHEN** the last successful update was 9 days ago, the threshold is 7 days, and the user opens a terminal
- **THEN** the shell prints a notice saying the last successful update was 9 days ago

#### Scenario: Updating normally, quiet repository
- **WHEN** the daily upgrade succeeded yesterday, but the central repository has had no commits for 12 days
- **THEN** opening a terminal prints no notice

#### Scenario: Profile without shared shell modules
- **WHEN** a user with the shared default profile opens a bash terminal while updates are stale
- **THEN** the notice is printed

### Requirement: Last successful update
The last successful update SHALL be the later of: the most recent successful completion of the daily automatic upgrade or of `nixos-central-upgrade` on NixOS, or of the home-manager automatic upgrade on a standalone home, whether or not it changed anything; and the time the newest generation was installed (which also covers manual rebuilds and the installation).

#### Scenario: Upgrade without changes
- **WHEN** the daily upgrade succeeds but produces the same system as before
- **THEN** it counts as the last successful update

#### Scenario: Failed upgrade
- **WHEN** the daily upgrade fails, e.g. because the machine is offline or the build fails
- **THEN** the last successful update stays at the previous successful run

#### Scenario: Manual switch on a standalone home
- **WHEN** the home-manager auto-upgrade has failed for 10 days, and the user ran `home-manager switch` with a changed configuration today
- **THEN** the last successful update is today

#### Scenario: No upgrade recorded yet
- **WHEN** a machine was installed 3 days ago and no upgrade has completed since
- **THEN** the last successful update is 3 days ago

### Requirement: Ages in the notice
The notice SHALL state, in whole days, how long ago the last successful update was, how old the running configuration is, and how old the pinned central revision is. The running configuration's age is the time since it was installed as a generation (NixOS system generation, or active home-manager generation on a standalone home). The central revision's age is the time since the commit date of `central` in the machine's or home's flake lock file.

#### Scenario: All ages known
- **WHEN** the notice is printed, the last successful update was 9 days ago, the running system generation was installed 15 days ago and the pinned central revision was committed 16 days ago
- **THEN** the notice states 9, 15 and 16 days respectively

#### Scenario: Update staged but not rebooted
- **WHEN** the daily upgrade staged a new generation, but the running system was installed 10 days ago
- **THEN** the running system's age is reported as 10 days

### Requirement: Actionable hint
The notice SHALL include what to do: if a newer system generation is already staged, to reboot; otherwise on NixOS to run `nixos-central-upgrade` or look at the upgrade's log, and on a standalone home how to check the home-manager auto-upgrade.

#### Scenario: Staged update waiting
- **WHEN** the notice is printed and a newer generation is the default boot entry
- **THEN** the notice tells the user to reboot to use it

#### Scenario: Nothing staged on NixOS
- **WHEN** the notice is printed on a NixOS machine and no newer generation is staged
- **THEN** the notice suggests running `nixos-central-upgrade`

#### Scenario: Standalone home
- **WHEN** the notice is printed on a standalone home
- **THEN** the notice tells the user how to check the home-manager auto-upgrade

### Requirement: Threshold set by the profile
The threshold SHALL default to 7 days. A profile SHALL be able to change it, or turn the notice off entirely.

#### Scenario: Longer threshold
- **WHEN** profile `kt` sets the threshold to 14 days and the last successful update was 10 days ago
- **THEN** `kt` sees no notice

#### Scenario: Turned off
- **WHEN** a profile turns the notice off
- **THEN** no notice is printed regardless of the ages

### Requirement: Never disturbs the shell
Determining the ages MUST NOT make the shell fail to start, print errors, or noticeably delay it. An age that cannot be determined SHALL be left out of the notice; if the last successful update cannot be determined, nothing is printed. Non-interactive shells MUST NOT print the notice.

#### Scenario: Tried branch running
- **WHEN** a branch activated with `nixos-central-try` is running and updates are stale
- **THEN** the shell starts normally and the notice leaves out the running system's age

#### Scenario: Lock file missing
- **WHEN** the flake lock file cannot be read
- **THEN** the shell starts normally without error output

#### Scenario: Script runs a command
- **WHEN** a non-interactive shell runs a command, e.g. `ssh foo uptime` or `bash -c ...`
- **THEN** the output contains no notice
