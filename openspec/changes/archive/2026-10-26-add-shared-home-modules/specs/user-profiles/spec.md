# Spec Delta

## ADDED Requirements

### Requirement: Profile selects the login shell
A profile SHALL be able to select the user's login shell among bash, fish and zsh; bash is the default. The selected shell MUST be usable without further configuration in the profile. On a NixOS machine, the primary user's login shell SHALL be the selected shell.

#### Scenario: Profile selects fish on NixOS
- **WHEN** `kt`'s profile selects fish and machine `foo` has primary user `kt`
- **THEN** after the next update and a new login, `kt`'s login shell on `foo` is fish

#### Scenario: No selection
- **WHEN** a profile does not select a shell
- **THEN** the user's login shell is bash

#### Scenario: Shell selected without its module
- **WHEN** a profile selects zsh but does not include the shared `zsh` module
- **THEN** the build succeeds and zsh is installed and works as the login shell

#### Scenario: Standalone home
- **WHEN** a standalone home's profile selects fish
- **THEN** fish is installed and configured, and the login shell is left unchanged (see `home-installer`)
