# Spec Delta

## ADDED Requirements

### Requirement: Installer detects NVIDIA GPUs
The installer SHALL look for an NVIDIA display controller before any disk is modified. If it finds none and `--nvidia` was not passed, it MUST ask nothing about NVIDIA and record `nvidia = null`.

#### Scenario: Machine without NVIDIA GPU
- **WHEN** the installer runs on a machine with no NVIDIA display controller and without NVIDIA flags
- **THEN** it asks no NVIDIA question and the machine flake records `nvidia = null`

### Requirement: Installer confirms the NVIDIA driver
When an NVIDIA GPU is found and no NVIDIA flag was passed, the installer SHALL show the GPU and what it would record, state that the open kernel modules need a Turing or newer GPU, and ask whether to install the driver, suggesting yes. Declining MUST record `nvidia = null`.

#### Scenario: Driver accepted
- **WHEN** an NVIDIA GPU is found and the user accepts the suggestion
- **THEN** the machine flake records the detected NVIDIA facts

#### Scenario: Driver declined
- **WHEN** an NVIDIA GPU is found and the user declines
- **THEN** the machine flake records `nvidia = null`

### Requirement: Installer records PRIME only for hybrid laptops
The installer SHALL record bus IDs only when the machine has an NVIDIA GPU, an Intel or AMD integrated GPU and a system battery. Bus IDs MUST use decimal numbers, whatever their hexadecimal form in the PCI address. Batteries of peripherals MUST NOT count as a system battery. In every other case with an NVIDIA GPU, it SHALL record `nvidia = { }`.

#### Scenario: Hybrid laptop
- **WHEN** the machine has an Intel GPU at `0000:00:02.0`, an NVIDIA GPU at `0000:01:00.0` and a system battery
- **THEN** the machine flake records `intelBusId = "PCI:0@0:2:0"` and `nvidiaBusId = "PCI:1@0:0:0"`

#### Scenario: Hexadecimal PCI address
- **WHEN** a hybrid laptop's NVIDIA GPU is at `0000:0a:00.0`
- **THEN** the machine flake records `nvidiaBusId = "PCI:10@0:0:0"`

#### Scenario: AMD hybrid laptop
- **WHEN** the machine has an AMD integrated GPU, an NVIDIA GPU and a system battery
- **THEN** the machine flake records `amdgpuBusId` and `nvidiaBusId`

#### Scenario: Desktop with an enabled integrated GPU
- **WHEN** the machine has an Intel GPU and an NVIDIA GPU, and no system battery
- **THEN** the machine flake records `nvidia = { }`

#### Scenario: Desktop with a wireless mouse
- **WHEN** the machine has an Intel GPU and an NVIDIA GPU, and the only battery reported belongs to a wireless mouse
- **THEN** the machine flake records `nvidia = { }`

#### Scenario: Laptop without an integrated GPU
- **WHEN** the machine has a system battery and an NVIDIA GPU as its only display controller
- **THEN** the machine flake records `nvidia = { }`

### Requirement: NVIDIA flags answer the question
The installer SHALL accept `--nvidia` and `--no-nvidia`. `--nvidia` MUST record the detected NVIDIA facts without asking and abort before any disk is modified when no NVIDIA GPU is found. `--no-nvidia` MUST record `nvidia = null` without asking. Passing both MUST abort before any disk is modified.

#### Scenario: --nvidia on an NVIDIA machine
- **WHEN** the user passes `--nvidia` and an NVIDIA GPU is found
- **THEN** the installer asks no NVIDIA question and records the detected facts

#### Scenario: --nvidia without an NVIDIA GPU
- **WHEN** the user passes `--nvidia` and no NVIDIA GPU is found
- **THEN** the installer explains this and exits non-zero without modifying any disk

#### Scenario: --no-nvidia on an NVIDIA machine
- **WHEN** the user passes `--no-nvidia` and an NVIDIA GPU is found
- **THEN** the installer asks no NVIDIA question and the machine flake records `nvidia = null`

#### Scenario: Both flags
- **WHEN** the user passes `--nvidia --no-nvidia`
- **THEN** the installer explains the conflict and exits non-zero without modifying any disk

### Requirement: NVIDIA's download server is checked when NVIDIA is selected
When the NVIDIA driver is selected, the installer SHALL verify that `download.nvidia.com` is reachable before any disk is modified, and abort with an actionable message if not. When it is not selected, it MUST NOT contact that server.

#### Scenario: NVIDIA's server unreachable
- **WHEN** the NVIDIA driver is selected and `download.nvidia.com` cannot be reached
- **THEN** the installer aborts without modifying any disk and offers the network check or `--no-nvidia` as ways forward

#### Scenario: No NVIDIA selected
- **WHEN** the machine records `nvidia = null` and `download.nvidia.com` cannot be reached
- **THEN** the installation continues

## MODIFIED Requirements

### Requirement: Installer accepts optional flags
The installer SHALL accept `--hostname`, `--user`, `--desktop`, `--disk`, `--private`, `--profile`, `--nvidia`, and `--no-nvidia`, passed via `sh -s -- <flags>`. A value given as a flag MUST NOT be prompted for. Unknown flags MUST abort with a usage message before any disk is modified.

#### Scenario: All machine facts given as flags
- **WHEN** the user runs the installer with `--hostname foo --user alice --desktop kde`
- **THEN** the installer does not ask for hostname, username, or desktop

#### Scenario: Unknown flag
- **WHEN** the user passes `--colour blue`
- **THEN** the installer prints usage and exits non-zero without modifying any disk

#### Scenario: Overlay and profile given as flags
- **WHEN** the user passes `--private git+ssh://git@github.com/alice/private --profile developer`
- **THEN** the installer does not ask whether to set up an overlay, for its URL, or for the profile

#### Scenario: Profile without overlay
- **WHEN** the user passes `--profile developer` without `--private`
- **THEN** the installer explains that a profile can only be chosen together with a private overlay and exits non-zero before modifying any disk

### Requirement: Installer produces a centrally managed system
The installer SHALL generate hardware configuration for the machine, write a per-machine flake (see `host-configuration`) to `/etc/nixos` on the target, install the system from it, and print a summary (hostname, user, desktop, disk, and, if set up, the NVIDIA driver and the private overlay and profile) before rebooting on user confirmation.

#### Scenario: Successful install
- **WHEN** installation completes
- **THEN** `/etc/nixos` on the installed system contains the per-machine flake and hardware configuration, and the installer prints the summary and offers to reboot

#### Scenario: Successful install with overlay
- **WHEN** installation with the private overlay `git+ssh://git@github.com/alice/private` and profile `developer` completes
- **THEN** the summary names the overlay URL and the profile

#### Scenario: Successful install with NVIDIA
- **WHEN** installation with the NVIDIA driver completes on a hybrid laptop
- **THEN** the summary says the NVIDIA driver is installed with PRIME offload

#### Scenario: Install step fails
- **WHEN** any installation step fails
- **THEN** the installer stops, prints which step failed and the path of a log file, and does not reboot
