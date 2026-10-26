# Spec Delta

## MODIFIED Requirements

### Requirement: Preflight checks fail early
Before any prompt that leads to disk changes, the installer SHALL verify it runs on a NixOS live image, booted in UEFI mode, with network access to GitHub, and SHALL obtain root privileges (via sudo if needed). Any failed check MUST abort with an actionable message.

#### Scenario: Legacy BIOS boot
- **WHEN** the machine was booted in legacy BIOS mode
- **THEN** the installer aborts and tells the user to boot the USB image in UEFI mode

#### Scenario: No network
- **WHEN** GitHub is not reachable
- **THEN** the installer aborts and suggests connecting to the network (e.g. with `nmtui`)

#### Scenario: Not a live image
- **WHEN** the installer is run on an installed Linux system that is not NixOS
- **THEN** it aborts before asking for root privileges, and the message includes the one-line command for the home installer

#### Scenario: Installed NixOS
- **WHEN** the installer is run on an installed NixOS machine
- **THEN** it aborts before asking for root privileges and tells the user to boot the NixOS installation image
