# Spec Delta

## MODIFIED Requirements

### Requirement: Shared modules work on NixOS and standalone
Every shared module SHALL build as part of a profile on a NixOS machine and in a standalone home on `x86_64-linux`, and SHALL evaluate in a standalone home on `aarch64-linux`. The central repository SHALL verify this with a test profile that includes every shared module, independent of any personal profile.

#### Scenario: Same module on both
- **WHEN** a profile includes all shared modules and is used by NixOS machine `foo` and a standalone home on Ubuntu
- **THEN** both build, and both contain the tools and settings of the included modules

#### Scenario: ARM standalone home
- **WHEN** a standalone home on `aarch64-linux` uses a profile that includes all shared modules
- **THEN** its configuration evaluates without errors

#### Scenario: No personal profile in the repository
- **WHEN** the central repository contains no personal profile at all
- **THEN** every shared module is still evaluated by the repository's checks
