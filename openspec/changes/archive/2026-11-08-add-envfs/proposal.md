# Proposal

## Why

Scripts and tools written for other Linux distributions hard-code paths such
as `#!/bin/bash`, `#!/usr/bin/python3` or `/usr/bin/git`. On NixOS only
`/bin/sh` and `/usr/bin/env` exist, so these scripts fail with "bad
interpreter: No such file or directory" until the user edits them or wraps
them. Users coming from other distributions hit this constantly (downloaded
install scripts, project `Makefile`s, IDE tooling, scripts in Git
repositories shared with non-NixOS colleagues).

## What Changes

- Every NixOS machine (all desktops, including `none`) gets **envfs**:
  `/usr/bin` and `/bin` show every program the calling process can find on its
  `PATH`, so `/usr/bin/bash`, `/bin/bash`, `/usr/bin/python3` (when Python is
  installed) and so on resolve to the Nix-installed program.
- `/bin/sh` and `/usr/bin/env` keep working exactly as today, also for
  processes without a `PATH`.
- `/usr/bin/bash` and `/bin/bash` also work for processes without a `PATH`
  (e.g. some systemd services or `env -i`), because bash is the interpreter
  scripts expect most often.
- Out of scope: running dynamically linked binaries built for other
  distributions (that is `nix-ld`, a separate change), libraries under
  `/usr/lib`, standalone homes on other distributions (they already have a
  real `/usr/bin`), and the installation image.

## Capabilities

### New Capabilities
- `fhs-executables`: conventional executable paths (`/usr/bin/<name>`,
  `/bin/<name>`) resolve to installed programs on NixOS machines.

### Modified Capabilities
<!-- none: "Shared base configuration" in host-configuration lists boot,
     network and Nix settings; this behavior gets its own capability. -->

## Impact

- New base module `modules/base/envfs.nix`, imported from
  `modules/base/default.nix`; applies to every machine built by the central
  host builder. Existing machine flakes need no edits.
- `/usr/bin` and `/bin` become mount points (FUSE and a bind mount) instead of
  directories created by activation scripts. A process sees the programs on
  *its own* `PATH`, so results differ per user/service.
- New VM check in `nixos-central-internal/tests/default.nix`.
- README: short section explaining `/usr/bin/<name>` and its limits; test list
  in Development.
