# Spec Delta

## ADDED Requirements

### Requirement: Profiles can use packages from nixpkgs-unstable
User profiles and NixOS modules in the central repository SHALL be able to refer to packages of the locked nixpkgs-unstable input as `pkgs.unstable.<name>`, with the same package configuration (e.g. unfree allowed) as the stable packages. Packages that are not referred to this way MUST come from the stable nixpkgs.

#### Scenario: Newer package in a profile
- **WHEN** `alice`'s profile adds `pkgs.unstable.helix` to her packages
- **THEN** after the next update `alice` has `helix` at the version of the locked nixpkgs-unstable revision

#### Scenario: Unfree package from unstable
- **WHEN** a profile adds an unfree package via `pkgs.unstable`
- **THEN** the system builds without additional configuration

#### Scenario: Ad-hoc shells unaffected
- **WHEN** a user runs `nix-shell -p hello`
- **THEN** `hello` comes from the system's stable nixpkgs, not from unstable
