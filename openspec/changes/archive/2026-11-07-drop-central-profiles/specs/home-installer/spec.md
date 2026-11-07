# Spec Delta

## ADDED Requirements

### Requirement: Home installer does not select a profile
The home installer SHALL NOT ask for a profile and SHALL NOT record one in the local flake. Given `--profile`, it MUST abort before writing any file, with a message that profiles come from a private overlay and are chosen with `nixos-central private setup --profile <name>` after installation.

#### Scenario: Interactive install
- **WHEN** user `kt` runs the home installer without flags
- **THEN** it does not ask for a profile, and the home is built from the base configuration

#### Scenario: Profile flag from an old instruction
- **WHEN** the home installer is run with `--profile kt`
- **THEN** it aborts before writing any file, and the message names `nixos-central private setup --profile kt`

## MODIFIED Requirements

### Requirement: Home installer accepts optional flags
The home installer SHALL accept its options via `sh -s -- <flags>`. A value given as a flag MUST NOT be prompted for. Unknown flags MUST abort with a usage message before any file is written.

#### Scenario: Non-interactive install
- **WHEN** the home installer is run with the GPU setup and Nix install answered via flags
- **THEN** it completes without prompting

#### Scenario: Unknown flag
- **WHEN** the home installer is run with `--disk /dev/sda`
- **THEN** it aborts with a usage message and writes nothing

### Requirement: Home installer produces a centrally managed home
The home installer SHALL write the local flake (see `home-configuration`), activate it with the home-manager version pinned by the central repository, offer the one-time GPU setup, and print a summary: login name, automatic updates, how to update manually, and how to add a private overlay with a profile. It MUST NOT change the user's login shell; if the activated configuration selects a different shell than the current login shell, it SHALL print how to change it.

#### Scenario: Successful install
- **WHEN** the home installer completes
- **THEN** the base configuration's programs are available in a new login session, the daily upgrade is scheduled, and the summary is printed, including the `nixos-central private setup` command

#### Scenario: Profile uses fish
- **WHEN** the activated configuration selects fish and the login shell is bash
- **THEN** the login shell stays bash and the summary explains how to switch to fish

#### Scenario: Profile provides a shell it does not select
- **WHEN** the activated configuration includes the `zsh` module but selects bash, and the login shell is bash
- **THEN** the summary does not suggest switching shells

## REMOVED Requirements

### Requirement: Profile is selected from the central repository
**Reason**: The central repository no longer holds profiles to select from. Replaced by "Home installer does not select a profile".
**Migration**: Install without `--profile`, then run `nixos-central private setup [<flake-url>] --profile <name>` to add the overlay and choose its profile.
