# home-modules Specification

## Purpose

Defines shared, opt-in building blocks of a user environment in the central repository: profiles include them instead of copying packages and settings, on NixOS machines and standalone homes alike.

## Requirements

### Requirement: Shared modules are opt-in per profile
The central repository SHALL provide shared home modules that a profile includes explicitly. A shared module MUST NOT take effect for any profile that does not include it, and the base configuration MUST NOT include any.

#### Scenario: Profile includes a module
- **WHEN** profile `kt` includes the `git` module
- **THEN** after the next update `kt`'s environment has the tools and settings of `git`

#### Scenario: Profile without the module
- **WHEN** a user has no private overlay and gets only the base configuration
- **THEN** none of the tools or settings of the shared modules are part of their environment

### Requirement: Shared modules are not profiles
Shared modules SHALL NOT be resolved as profiles. Neither the shared modules nor the base configuration MUST be selectable as an overlay profile by name.

#### Scenario: Selectable profiles after adding a module
- **WHEN** a shared module is added to the central repository and a machine's overlay has the profiles `default` and `kt`
- **THEN** the profiles that machine can record are still `default` and `kt` only

#### Scenario: Login name equals a module name
- **WHEN** a machine is installed with user `git`, and its overlay has a default profile but no `git` profile
- **THEN** that user gets the base configuration plus the overlay's default profile, not the `git` module

### Requirement: Shared modules work on NixOS and standalone
Every shared module SHALL build as part of a profile on a NixOS machine and in a standalone home on `x86_64-linux`, and SHALL evaluate in a standalone home on `aarch64-linux`. The central repository SHALL verify this with a test profile, kept with its tests, that includes every shared module.

#### Scenario: Same module on both
- **WHEN** a profile includes all shared modules and is used by NixOS machine `foo` and a standalone home on Ubuntu
- **THEN** both build, and both contain the tools and settings of the included modules

#### Scenario: ARM standalone home
- **WHEN** a standalone home on `aarch64-linux` uses a profile that includes all shared modules
- **THEN** its configuration evaluates without errors

#### Scenario: No personal profile in the repository
- **WHEN** the central repository contains no personal profile, as is always the case now
- **THEN** every shared module is still evaluated by the repository's checks

### Requirement: Module defaults can be overridden
Settings that a shared module makes about how a tool behaves (as opposed to which tools are installed) SHALL be defaults that the including profile can override by setting the same option, without forcing.

#### Scenario: Profile changes a workflow default
- **WHEN** profile `kt` includes `git` and sets git's pull behavior to merge instead of rebase
- **THEN** `kt`'s git configuration uses merge, and the build succeeds

### Requirement: Shared modules carry no personal identity
Shared modules MUST NOT set personal data such as names, email addresses, keys, or account-specific paths. These belong in the profile.

#### Scenario: Module included without identity
- **WHEN** a profile includes `git` without setting a user name
- **THEN** the build succeeds and no name or email from another person is configured

### Requirement: General tools module
The `general-tools` module SHALL provide everyday command-line utilities that are not specific to software development: file transfer, disk usage, and network lookups and monitoring.

#### Scenario: Utilities available
- **WHEN** a profile includes `general-tools`
- **THEN** commands such as `rsync`, `dust`, `ncdu`, `whois`, `iftop` and `nslookup` are available to the user

### Requirement: git module
The `git` module SHALL provide git with Git LFS and these defaults: rebase on pull with automatic stashing, and push without manual upstream setup.

#### Scenario: First push of a new branch
- **WHEN** a user of a profile with `git` runs `git push` on a new local branch
- **THEN** the branch is pushed and set to track the remote branch without extra flags

### Requirement: zsh module
The `zsh` module SHALL provide zsh with completion, autosuggestions, syntax highlighting and a shared, deduplicated history.

#### Scenario: Suggestions while typing
- **WHEN** a user of a profile with `zsh` types the start of a command they ran before
- **THEN** zsh suggests the rest of it from history
