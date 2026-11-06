# central-command Specification

## Purpose

Gives users one command, `nixos-central`, for everything they do by hand with their machine or standalone home: updating, inspecting updates, managing the private overlay and trying branches. It can be discovered through help, shell completion and an interactive menu.

## Requirements

### Requirement: One command with subcommands
Every NixOS machine and every standalone home SHALL provide exactly one user command, `nixos-central`, that runs a subcommand given as its first argument. On NixOS machines its subcommands SHALL be `upgrade`, `diff`, `status`, `private` and `try`. On standalone homes they SHALL be `upgrade`, `diff`, `status` and `private`. Arguments after the subcommand MUST be passed to it unchanged.

#### Scenario: Subcommand with arguments
- **WHEN** a user on a NixOS machine runs `nixos-central upgrade --private`
- **THEN** the overlay-only upgrade runs, exactly as described for `upgrade --private`

#### Scenario: Subcommand not available here
- **WHEN** a user of a standalone home runs `nixos-central try main`
- **THEN** the command prints the subcommands available on this home, exits with an error and changes nothing

#### Scenario: Unknown subcommand
- **WHEN** a user runs `nixos-central frobnicate`
- **THEN** the command says that `frobnicate` is not a subcommand, prints the available subcommands, exits with an error and changes nothing

#### Scenario: All subcommands on a NixOS machine
- **WHEN** a user on a NixOS machine runs `nixos-central status`, `nixos-central diff` and `nixos-central try --help`
- **THEN** each runs its subcommand, and there is only one `nixos-central` on the user's PATH

### Requirement: Old command names are gone
The commands `nixos-central-upgrade`, `nixos-central-try`, `nixos-central-diff`, `nixos-central-private` and `nixos-central-update-notice` MUST NOT be on the user's PATH, on NixOS machines or on standalone homes.

#### Scenario: Old name typed
- **WHEN** a user runs `nixos-central-upgrade` after updating to this version
- **THEN** the shell reports that the command is not found

### Requirement: Help
`nixos-central help`, `nixos-central --help` and `nixos-central -h` SHALL print every subcommand available on this machine or home, each with a one-line description and its arguments, and exit successfully. Options that only scripts use, such as `status --if-stale`, MUST NOT be listed.

#### Scenario: Help on a standalone home
- **WHEN** a user of a standalone home runs `nixos-central --help`
- **THEN** it lists `upgrade`, `diff`, `status` and `private` with descriptions, does not list `try`, and exits with status 0

### Requirement: Interactive chooser
When `nixos-central` is run without arguments and both its input and output are a terminal, it SHALL show a menu of the available subcommands with their descriptions, except `try`. It SHALL then run the chosen subcommand without arguments. Cancelling the menu MUST change nothing and exit with an error.

#### Scenario: Pick a subcommand
- **WHEN** a user runs `nixos-central` in a terminal and picks `diff`
- **THEN** the output is the same as from `nixos-central diff`

#### Scenario: try is not offered
- **WHEN** a user on a NixOS machine runs `nixos-central` in a terminal
- **THEN** the menu offers `upgrade`, `diff`, `status` and `private`, but not `try`

#### Scenario: Cancelled
- **WHEN** the user presses Escape or Ctrl-C in the menu
- **THEN** nothing runs, nothing changes and the command exits with an error

### Requirement: No chooser without a terminal
When `nixos-central` is run without arguments and its input or output is not a terminal, it MUST NOT wait for input. It SHALL print the help to standard error and exit with an error.

#### Scenario: Piped
- **WHEN** a script runs `nixos-central | cat` or `nixos-central < /dev/null`
- **THEN** the help is printed, the command exits with a non-zero status right away, and nothing runs

### Requirement: Shell completion
In interactive bash, zsh and fish shells, `nixos-central` SHALL complete its subcommands available on this machine or home and the subcommands' fixed options and actions (`upgrade --private`, `private setup`, `private remove`, `private setup … --profile`). Branch names for `try` and URLs for `private setup` are not completed.

#### Scenario: Complete a subcommand
- **WHEN** a user types `nixos-central up` and presses Tab in fish
- **THEN** the shell completes it to `nixos-central upgrade`

#### Scenario: Complete a private action
- **WHEN** a user types `nixos-central private ` and presses Tab in bash
- **THEN** the shell offers `setup` and `remove`
