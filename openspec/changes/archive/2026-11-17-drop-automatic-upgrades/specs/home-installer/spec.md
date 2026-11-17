## MODIFIED Requirements

### Requirement: Home installer produces a centrally managed home
The home installer SHALL write the local flake (see `home-configuration`), activate it with the home-manager version pinned by the central repository, offer the one-time GPU setup, and print a summary: login name, how to update (`nixos-central upgrade`), and how to add a private overlay with a profile. It MUST NOT change the user's login shell; if the activated configuration selects a different shell than the current login shell, it SHALL print how to change it.

#### Scenario: Successful install
- **WHEN** the home installer completes
- **THEN** the base configuration's programs are available in a new login session, no automatic upgrade is scheduled, and the summary is printed, including the `nixos-central upgrade` and `nixos-central private setup` commands

#### Scenario: Profile uses fish
- **WHEN** the activated configuration selects fish and the login shell is bash
- **THEN** the login shell stays bash and the summary explains how to switch to fish

#### Scenario: Profile provides a shell it does not select
- **WHEN** the activated configuration includes the `zsh` module but selects bash, and the login shell is bash
- **THEN** the summary does not suggest switching shells
