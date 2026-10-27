# Spec Delta

## ADDED Requirements

### Requirement: Showing what the last home update changed
Each standalone home SHALL provide a command `nixos-central-diff`, run as the user without root, that lists the packages added, removed and changed in version from the previous home generation to the current one, names both generation numbers, and changes nothing.

#### Scenario: After an update
- **WHEN** the daily upgrade or `nixos-central-upgrade` has activated a new home generation and the user runs `nixos-central-diff`
- **THEN** the command lists the package changes from the previous generation to the current one

#### Scenario: No previous generation
- **WHEN** the home has only one generation and the user runs `nixos-central-diff`
- **THEN** the command says there is no earlier generation to compare with and succeeds

#### Scenario: Unknown argument
- **WHEN** the user runs `nixos-central-diff` with any argument
- **THEN** the command prints its usage, exits with an error and changes nothing
