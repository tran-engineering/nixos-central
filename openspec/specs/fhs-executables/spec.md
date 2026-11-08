# fhs-executables Specification

## Purpose

Lets scripts and tools written for other Linux distributions find programs at
their conventional paths (`/usr/bin/<name>`, `/bin/<name>`) on NixOS machines,
without editing their shebangs or hard-coded paths.

## Requirements

### Requirement: Programs on PATH appear under /usr/bin and /bin
Every NixOS machine built from the central repository, whatever its desktop, SHALL make `/usr/bin/<name>` and `/bin/<name>` resolve to the program `<name>` that the accessing process would find on its own `PATH`. A name that is not on the process's `PATH` and has no fallback (see below) MUST NOT exist under these paths.

#### Scenario: Script with a bash shebang
- **WHEN** a user runs an executable script starting with `#!/bin/bash` or `#!/usr/bin/bash`
- **THEN** the script runs with the system's bash

#### Scenario: Program installed by the user's profile
- **WHEN** a user's profile installs `python3` and the user runs `/usr/bin/python3 --version`
- **THEN** the Python from the user's profile answers

#### Scenario: Program only on PATH temporarily
- **WHEN** a user runs `nix shell nixpkgs#hello -c /usr/bin/hello`
- **THEN** `hello` from that shell runs

#### Scenario: Program not installed
- **WHEN** a process whose `PATH` contains no `hello` accesses `/usr/bin/hello`
- **THEN** the path does not exist and running it fails with "No such file or directory"

#### Scenario: Machine without a desktop
- **WHEN** a machine uses desktop `none`
- **THEN** `/usr/bin/bash` resolves to bash for a logged-in user

### Requirement: Essential paths work without a PATH
`/bin/sh`, `/usr/bin/env`, `/bin/bash` and `/usr/bin/bash` SHALL resolve to the system's shell, `env` and bash also for a process whose environment has no `PATH` or a `PATH` without them.

#### Scenario: Empty environment
- **WHEN** a process runs `env -i /usr/bin/bash -c 'echo ok'`, `env -i /bin/sh -c 'echo ok'` or `env -i /usr/bin/env true`
- **THEN** each command succeeds

#### Scenario: Service with a bash shebang
- **WHEN** a systemd service without `bash` on its `PATH` starts a script whose shebang is `#!/usr/bin/bash`
- **THEN** the script runs with the system's bash

### Requirement: Boot is not blocked by the executable paths
A machine SHALL boot to its login (graphical or console) and its system services SHALL start when providing `/usr/bin` and `/bin` fails, so that a failure of this feature never makes the machine unusable.

#### Scenario: Normal boot
- **WHEN** a machine with this feature boots
- **THEN** it reaches its login without failed units related to `/usr/bin` or `/bin`

#### Scenario: Existing machine updates
- **WHEN** an existing machine updates to a central revision with this feature and switches or reboots
- **THEN** `/usr/bin/bash` works after the reboot and `/bin/sh` and `/usr/bin/env` keep working throughout
