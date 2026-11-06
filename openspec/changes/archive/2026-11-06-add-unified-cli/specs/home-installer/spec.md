# Spec Delta

## MODIFIED Requirements

### Requirement: Home installer preflight checks
Before writing any file, the home installer SHALL verify that it runs on Linux on a supported architecture, that the machine is not NixOS, and that GitHub is reachable. Any failed check MUST abort with an actionable message.

#### Scenario: Run on NixOS
- **WHEN** the home installer is run on an installed NixOS machine
- **THEN** it aborts and points to the NixOS installer for new machines and to `nixos-central upgrade` for managed ones

#### Scenario: Unsupported platform
- **WHEN** the home installer is run on macOS or on a 32-bit system
- **THEN** it aborts, naming the supported platforms

#### Scenario: No network
- **WHEN** GitHub is not reachable
- **THEN** the home installer aborts and asks the user to connect to the network
