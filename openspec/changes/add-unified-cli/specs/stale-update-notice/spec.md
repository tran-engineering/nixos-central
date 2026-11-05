# Spec Delta

## MODIFIED Requirements

### Requirement: Last successful update
The last successful update SHALL be the later of: the most recent successful completion of the daily automatic upgrade or of `nixos-central upgrade` on NixOS, or of the home-manager automatic upgrade on a standalone home, whether or not it changed anything; and the time the newest generation was installed (which also covers manual rebuilds and the installation).

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

### Requirement: Actionable hint
The notice SHALL include what to do: if a newer system generation is already staged, to reboot; otherwise on NixOS to run `nixos-central upgrade` or look at the upgrade's log, and on a standalone home how to check the home-manager auto-upgrade.

#### Scenario: Staged update waiting
- **WHEN** the notice is printed and a newer generation is the default boot entry
- **THEN** the notice tells the user to reboot to use it

#### Scenario: Nothing staged on NixOS
- **WHEN** the notice is printed on a NixOS machine and no newer generation is staged
- **THEN** the notice suggests running `nixos-central upgrade`

#### Scenario: Standalone home
- **WHEN** the notice is printed on a standalone home
- **THEN** the notice tells the user how to check the home-manager auto-upgrade

### Requirement: Shown on demand
The notice SHALL also be available as the subcommand `nixos-central status`. Run by hand, it MUST print the notice with the ages and hint regardless of the threshold, also when the notice is turned off; a last successful update that cannot be determined is shown as unknown. Shells print it only when stale (`nixos-central status --if-stale`).

#### Scenario: Recent update
- **WHEN** the last successful update was yesterday and the user runs `nixos-central status`
- **THEN** it prints that the last successful update was 1 day ago, with the other ages and the hint

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
