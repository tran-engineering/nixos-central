# nvidia-graphics Specification

## Purpose

Defines how a machine whose flake records the `nvidia` fact is configured: the open kernel modules, the driver channel, PRIME offload on hybrid laptops, power management, GPU access from containers, and how driver builds are verified.

## Requirements

### Requirement: Machines with the NVIDIA fact use the open kernel modules
A machine whose flake sets the `nvidia` fact SHALL use NVIDIA's open kernel modules with NVIDIA's proprietary userspace, on every desktop including `none`. The closed kernel modules MUST NOT be selectable through the fact. A machine without the fact, or with `nvidia = null`, MUST get no NVIDIA driver.

#### Scenario: NVIDIA fact set
- **WHEN** a machine flake sets `nvidia = { }`
- **THEN** the system builds with the open kernel modules and the `nouveau` module blacklisted

#### Scenario: Fact absent
- **WHEN** a machine flake does not set `nvidia` or sets it to `null`
- **THEN** the system has no NVIDIA driver and no NVIDIA container toolkit

#### Scenario: Headless machine
- **WHEN** a machine with desktop `none` sets `nvidia = { }`
- **THEN** the system builds with the open kernel modules and starts no graphical session

### Requirement: Driver channel is selectable per machine
The `nvidia` fact SHALL accept a `channel` of `"stable"` or `"unstable"`, defaulting to `"stable"`. `"stable"` MUST use the production driver of the system's nixpkgs. `"unstable"` MUST use the newest driver branch of the nixos-unstable input. Every channel's kernel modules MUST be built against the machine's own kernel.

#### Scenario: Channel not set
- **WHEN** a machine flake sets `nvidia = { }`
- **THEN** the driver is the production driver of the system's nixpkgs

#### Scenario: Unstable channel
- **WHEN** a machine flake sets `nvidia = { channel = "unstable"; }`
- **THEN** the driver version is that of the nixos-unstable input's newest branch, and the machine's kernel stays the one from the system's nixpkgs

#### Scenario: Unknown channel
- **WHEN** a machine flake sets `nvidia = { channel = "beta"; }`
- **THEN** evaluation fails and names the valid channels

### Requirement: Hybrid machines use PRIME offload
When the `nvidia` fact records the NVIDIA bus ID and one integrated GPU bus ID (Intel or AMD), the machine SHALL render on the integrated GPU by default and provide the `nvidia-offload` command, which runs a program on the NVIDIA GPU. Without bus IDs, PRIME MUST NOT be configured.

#### Scenario: Intel hybrid laptop
- **WHEN** a machine flake sets `nvidia = { intelBusId = "PCI:0@0:2:0"; nvidiaBusId = "PCI:1@0:0:0"; }`
- **THEN** the session renders on the Intel GPU and `nvidia-offload <program>` runs the program on the NVIDIA GPU

#### Scenario: AMD hybrid laptop
- **WHEN** a machine flake sets `nvidia = { amdgpuBusId = "PCI:5@0:0:0"; nvidiaBusId = "PCI:1@0:0:0"; }`
- **THEN** the session renders on the AMD GPU and `nvidia-offload <program>` runs the program on the NVIDIA GPU

#### Scenario: Desktop without bus IDs
- **WHEN** a machine flake sets `nvidia = { }`
- **THEN** PRIME is not configured and no `nvidia-offload` command is provided

#### Scenario: Incomplete bus IDs
- **WHEN** a machine flake sets only one of the NVIDIA bus ID and the integrated GPU bus IDs, or both an Intel and an AMD bus ID
- **THEN** evaluation fails and explains which bus IDs are required

### Requirement: NVIDIA machines suspend and save power
Every machine with the `nvidia` fact SHALL enable driver power management so that suspend and resume preserve the GPU's state. On a machine with PRIME offload, the NVIDIA GPU SHALL power down while no program uses it.

#### Scenario: Suspend and resume
- **WHEN** a machine with the fact is suspended and resumed
- **THEN** the graphical session and running programs continue to work

#### Scenario: NVIDIA GPU idle on a hybrid laptop
- **WHEN** no program is using the NVIDIA GPU of a machine with PRIME offload
- **THEN** the kernel reports the NVIDIA GPU's runtime power status as suspended

### Requirement: Containers can use the GPU
Every machine with the `nvidia` fact SHALL give Docker containers access to the GPU through CDI device names.

#### Scenario: Container requests the GPU
- **WHEN** the primary user runs `docker run --rm --device nvidia.com/gpu=all <image> nvidia-smi` on a machine with the fact
- **THEN** the command lists the machine's NVIDIA GPU

#### Scenario: Machine without the fact
- **WHEN** a machine does not set the fact
- **THEN** no NVIDIA CDI devices are provided

### Requirement: Driver builds are verified before reaching machines
The central repository's flake check SHALL build the open kernel modules and userspace of both channels against the system kernel, so that the weekly lock update does not reach machines when a channel's driver fails to build.

#### Scenario: Channel stops building
- **WHEN** a lock update makes the driver of either channel fail to build
- **THEN** `nix flake check` fails and the update is not merged
