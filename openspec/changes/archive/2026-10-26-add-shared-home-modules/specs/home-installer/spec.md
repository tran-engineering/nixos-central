# Spec Delta

## MODIFIED Requirements

### Requirement: Home installer produces a centrally managed home
The home installer SHALL write the local flake (see `home-configuration`), activate it with the home-manager version pinned by the central repository, offer the one-time GPU setup, and print a summary: login name, profile (personal or default), automatic updates, and how to update manually. It MUST NOT change the user's login shell; if the profile selects a different shell than the current login shell, it SHALL print how to change it.

#### Scenario: Successful install
- **WHEN** the home installer completes
- **THEN** the profile's programs are available in a new login session, the daily upgrade is scheduled, and the summary is printed

#### Scenario: Profile uses fish
- **WHEN** the chosen profile selects fish and the login shell is bash
- **THEN** the login shell stays bash and the summary explains how to switch to fish

#### Scenario: Profile provides a shell it does not select
- **WHEN** the chosen profile includes the `zsh` module but selects bash, and the login shell is bash
- **THEN** the summary does not suggest switching shells
