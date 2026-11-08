# Design

## Context

Today the base configuration leaves NixOS's defaults in place: activation
scripts create only `/bin/sh` and `/usr/bin/env` as symlinks. nixos-26.05 (the
pinned `nixpkgs`) ships `services.envfs` (`nixos/modules/tasks/filesystems/envfs.nix`):

- `/usr/bin` becomes an `envfs` FUSE mount that answers a lookup of `<name>`
  with a symlink to `<name>` on the **requesting process's** `PATH` (read from
  `/proc/<pid>/environ`), or to an entry of a fallback directory.
- `/bin` becomes a bind mount of `/usr/bin`.
- The fallback directory always contains `env` and `sh`
  (`environment.usrbinenv`, `environment.binsh`); more can be added with
  `services.envfs.extraFallbackPathCommands`.
- Both mounts are `nofail`; the module disables the `usrbinenv`/`binsh`
  activation scripts and, with a systemd initrd, creates `/sysroot/usr/bin`
  and `/sysroot/bin` to avoid known boot failures.
- In QEMU VMs (`virtualisation.qemu`) the mounts are applied with
  `mkVMOverride`, so VM checks see the real behavior.

The base modules live in `modules/base/` (one file per concern, imported from
`modules/base/default.nix`); VM checks live in
`nixos-central-internal/tests/default.nix` and use `testHost`.

## Goals / Non-Goals

**Goals:**
- Turn on envfs for every NixOS machine with a small, commented base module.
- Make `/usr/bin/bash` / `/bin/bash` independent of `PATH` via the fallback.
- A VM check that covers the scenarios in `specs/fhs-executables/spec.md`.

**Non-Goals:**
- An opt-out option (`nixos-central.*`). Machines that need to turn it off can
  set `services.envfs.enable = lib.mkForce false` in their own modules; a
  dedicated option can be added if someone asks.
- `nix-ld` / running foreign dynamically linked binaries.
- Any change to standalone homes or the ISO.

## Decisions

### envfs over alternatives
- **envfs (chosen):** upstream NixOS module, per-process resolution, so every
  program the user can run is reachable without listing it anywhere; profile
  and `nix shell` programs work too.
- **Static symlinks in `/usr/bin` (e.g. `systemd.tmpfiles` for bash, python…):**
  simple and no FUSE, but only covers a fixed list and points at system
  packages, not the user's profile. Rejected as it would grow forever.
- **`buildFHSEnv` / `steam-run` wrappers:** per-command, the user has to know
  about them; does not help shebangs. Rejected.

### Module placement
New `modules/base/envfs.nix` setting `services.envfs.enable = true`,
unconditional (all desktops). Follows the one-file-per-concern pattern and
keeps a header comment explaining the PATH-based behavior and the bash
fallback.

### bash fallback
`extraFallbackPathCommands = "ln -s ${pkgs.bashInteractive}/bin/bash $out/bash"`.
`bashInteractive` because `environment.binsh` defaults to it and it matches the
`bash` a user gets on `PATH`. Only bash is added: it is the most common
hard-coded interpreter; more fallbacks would pin packages into the closure for
rare cases. Others resolve via `PATH` as usual.

## Risks / Trade-offs

- [Results depend on the caller's `PATH`: `/usr/bin/python3` may exist for a
  user and not for a service or root] → Documented in the README; spec defines
  this as the intended behavior.
- [Lookups through FUSE are slower than a symlink] → Only `/usr/bin` and
  `/bin` lookups pay this; `/bin/sh`/`/usr/bin/env` costs were negligible in
  upstream use. Accepted.
- [Mount fails at boot → `/bin/sh` and `/usr/bin/env` missing, since their
  activation scripts are disabled] → Mounts are `nofail` so boot continues; the
  VM check asserts the mounts are active and the units are not failed. Risk
  accepted as upstream default behavior.
- [Software that writes into `/usr/bin` or expects to list it fully (e.g. some
  installers)] → Writes were already failing/meaningless on NixOS; listing
  `/usr/bin` shows little. Accepted.
- [Docker containers] → Containers have their own root filesystem; unaffected.
  Bind-mounting host `/usr/bin` into a container would not be meaningful
  anyway.

## Migration Plan

- Existing machines get envfs with their next automatic upgrade, which stages
  it for the next boot (`operation = "boot"`).
- `nixos-central upgrade` (a live `switch`) mounts it immediately; verified in
  a VM switching from a generation without envfs. The first switch logs
  `usr-bin.mount: Failed with result 'protocol'` and `Dependency failed for
  /bin` (systemd checks for the mount before the daemonizing `mount.envfs` has
  set it up), but both units end `active`/`success`, nothing is left in
  `systemctl --failed`, and `/bin/sh`, `/usr/bin/env` and `/usr/bin/bash` work
  right after the switch. The leftover `/bin/sh` and `/usr/bin/env` symlinks
  stay underneath the mounts, hidden.
- Rollback: boot the previous generation, or revert the module; `/bin/sh` and
  `/usr/bin/env` come back from the re-enabled activation scripts. A live
  `switch` back to a generation without envfs leaves envfs mounted (and
  working) until the next reboot.
