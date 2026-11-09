# Spec Delta

## ADDED Requirements

### Requirement: Upgrade reports driver changes that need a reboot
When `nixos-central upgrade` activates a configuration whose kernel is unchanged but whose kernel modules differ from the booted system's, such as a new NVIDIA driver, it SHALL tell the user that the new drivers are used after the next reboot and that programs using the GPU may fail until then. It MUST NOT reboot the machine.

#### Scenario: NVIDIA driver changed
- **WHEN** `nixos-central upgrade` activates a configuration with a new NVIDIA driver and the same kernel as the booted system
- **THEN** the command does not reboot and tells the user that the new drivers are used after the next reboot

#### Scenario: Kernel modules unchanged
- **WHEN** `nixos-central upgrade` activates a configuration with the same kernel and kernel modules as the booted system
- **THEN** the command prints no reboot hint
