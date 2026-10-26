# Spec Delta

## Purpose

Defines the one-line installer that sets up a user's environment from the central repository on a Linux machine without NixOS, running as that user and without touching disks or the system configuration.

## ADDED Requirements

### Requirement: Home installer is published at a stable URL
The home installer SHALL be served from `https://tran-engineering.github.io/nixos-central/home-only.sh` and SHALL be runnable as `curl -sL https://tran-engineering.github.io/nixos-central/home-only.sh | sh`. The published script MUST be the version from the central repository's default branch.

#### Scenario: One-line home install
- **WHEN** a user on Ubuntu runs `curl -sL https://tran-engineering.github.io/nixos-central/home-only.sh | sh`
- **THEN** the home installer starts and begins interactive setup

#### Scenario: Script update is published
- **WHEN** a change to the home installer is merged to the default branch
- **THEN** the URL serves the updated script after publication completes

### Requirement: Truncated home installer downloads do not execute partially
The home installer MUST perform no action unless the complete script has been received.

#### Scenario: Connection drops mid-download
- **WHEN** the download is interrupted before the end of the script
- **THEN** no file is written and no installation step runs

### Requirement: Home installer runs as the target user
The home installer SHALL set up the environment of the user running it, taking login name and home directory from that user, without prompting for them. It MUST refuse to run as root.

#### Scenario: Different login name
- **WHEN** user `khoi.tran` with home `/home/khoi.tran` runs the home installer
- **THEN** the standalone home is set up for `khoi.tran` in `/home/khoi.tran`

#### Scenario: Run as root
- **WHEN** the home installer is run as root (directly or via sudo)
- **THEN** it aborts, explaining that it must be run as the user whose environment is set up

### Requirement: Home installer preflight checks
Before writing any file, the home installer SHALL verify that it runs on Linux on a supported architecture, that the machine is not NixOS, and that GitHub is reachable. Any failed check MUST abort with an actionable message.

#### Scenario: Run on NixOS
- **WHEN** the home installer is run on an installed NixOS machine
- **THEN** it aborts and points to the NixOS installer for new machines and to `nixos-central-upgrade` for managed ones

#### Scenario: Unsupported platform
- **WHEN** the home installer is run on macOS or on a 32-bit system
- **THEN** it aborts, naming the supported platforms

#### Scenario: No network
- **WHEN** GitHub is not reachable
- **THEN** the home installer aborts and asks the user to connect to the network

### Requirement: Nix is installed if missing
If Nix is not available, the home installer SHALL explain that a multi-user Nix installation requires root, and install it only after the user confirms. If the user declines, it MUST abort without changes.

#### Scenario: Fresh distribution
- **WHEN** Nix is not installed and the user confirms
- **THEN** Nix is installed and the home installer continues

#### Scenario: Nix install declined
- **WHEN** Nix is not installed and the user declines
- **THEN** the home installer aborts and nothing is changed

### Requirement: Profile is selected from the central repository
The home installer SHALL accept `--profile <name>` and otherwise prompt with the list of selectable profiles of the central repository. The default SHALL be the profile named like the login name if it exists, else the shared default profile. Test profiles MUST NOT be offered. An unknown profile MUST be rejected (re-prompt interactively, abort for the flag).

#### Scenario: Matching personal profile
- **WHEN** user `kt` runs the home installer and the repository has a profile `kt`
- **THEN** the prompt offers `kt` as the default

#### Scenario: Pick another profile
- **WHEN** user `khoi.tran` runs the home installer and selects profile `kt`
- **THEN** `khoi.tran`'s home is built from profile `kt`

#### Scenario: No matching profile
- **WHEN** user `bob` runs the home installer and the repository has no `bob` profile
- **THEN** the prompt offers the shared default profile as the default

#### Scenario: Unknown profile flag
- **WHEN** the home installer is run with `--profile no-such-profile`
- **THEN** it aborts with a message listing the selectable profiles, before writing any file

### Requirement: Home installer accepts optional flags
The home installer SHALL accept its options via `sh -s -- <flags>`. A value given as a flag MUST NOT be prompted for. Unknown flags MUST abort with a usage message before any file is written.

#### Scenario: Non-interactive install
- **WHEN** the home installer is run with `--profile kt` and the GPU setup and Nix install are answered via flags
- **THEN** it completes without prompting

#### Scenario: Unknown flag
- **WHEN** the home installer is run with `--disk /dev/sda`
- **THEN** it aborts with a usage message and writes nothing

### Requirement: Existing local home flake is not overwritten silently
If `~/.config/home-manager` already contains files, the home installer SHALL show them and continue only if the user confirms. Existing files MUST be kept as a backup, not deleted.

#### Scenario: Previous home-manager setup
- **WHEN** `~/.config/home-manager/flake.nix` already exists and the user confirms
- **THEN** the existing files are moved to a backup location that the installer names, and the new local flake is written

#### Scenario: Confirmation declined
- **WHEN** `~/.config/home-manager` is not empty and the user declines
- **THEN** the home installer aborts and nothing is changed

### Requirement: Existing dotfiles are backed up on first activation
When the first activation would replace a file in the home directory that is not managed yet, the file SHALL be kept with a backup suffix instead of being overwritten or aborting the installation.

#### Scenario: Existing shell config
- **WHEN** `~/.bashrc` exists and the chosen profile manages it
- **THEN** the original is kept as `~/.bashrc.backup` and the profile's version is active

### Requirement: Home installer produces a centrally managed home
The home installer SHALL write the local flake (see `home-configuration`), activate it with the home-manager version pinned by the central repository, offer the one-time GPU setup, and print a summary: login name, profile (personal or default), automatic updates, and how to update manually. It MUST NOT change the user's login shell; if the profile sets a different shell, it SHALL print how to change it.

#### Scenario: Successful install
- **WHEN** the home installer completes
- **THEN** the profile's programs are available in a new login session, the daily upgrade is scheduled, and the summary is printed

#### Scenario: Profile uses fish
- **WHEN** the chosen profile enables fish and the login shell is bash
- **THEN** the login shell stays bash and the summary explains how to switch to fish
