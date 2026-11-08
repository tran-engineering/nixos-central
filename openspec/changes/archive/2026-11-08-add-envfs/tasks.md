# Tasks

## 1. envfs in the base configuration

- [x] 1.1 Add `modules/base/envfs.nix` with a header comment (PATH-based resolution, fallbacks) setting `services.envfs.enable = true` and `services.envfs.extraFallbackPathCommands` linking `${pkgs.bashInteractive}/bin/bash` to `$out/bash`; import it from `modules/base/default.nix`; verify `nix flake check --no-build` evaluates all `ci-*` hosts and `host-eval-ci-modules`, and that `nix eval .#nixosConfigurations.ci-none.config.services.envfs.enable` is `true`
- [x] 1.2 Add the `envfs` VM check in `nixos-central-internal/tests/default.nix` (node `machine`, `testHost { desktop = "none"; }`, `pkgs.hello` in `additionalPaths`): `usr-bin.mount` and `bin.mount` active and no failed units; as `alice`, `#!/bin/bash` and `#!/usr/bin/bash` scripts run; `/usr/bin/hello` fails but `nix shell nixpkgs#hello -c /usr/bin/hello` prints `Hello, world!`; `env -i /usr/bin/bash -c 'echo ok'`, `env -i /bin/bash -c true`, `env -i /bin/sh -c true` and `env -i /usr/bin/env true` succeed; a test systemd service with an empty `path` runs a `#!/usr/bin/bash` script successfully; verify `nix build .#checks.x86_64-linux.envfs` passes
- [x] 1.3 README: add a short section (e.g. "Scripts from other distributions" near "Installing apps") explaining that `/usr/bin/<name>` and `/bin/<name>` resolve to programs on the caller's `PATH`, that `/bin/sh`, `/usr/bin/env` and `/usr/bin/bash` always work, that a service or root may see different programs than the user, and that foreign prebuilt binaries are not covered; add `envfs` to the test descriptions in "Development"; verify the commands in the section in the VM from 1.2 (`nix run .#checks.x86_64-linux.envfs.driverInteractive` or equivalent)

## 2. Integration on real machines

- [x] 2.1 Build and boot a graphical CI host in a VM (`nixos-rebuild build-vm --flake .#ci-kde` or `ci-gnome`): reaches the GDM login, no failed units (`systemctl --failed`), and in the desktop session a terminal runs `/usr/bin/bash --version`
- [x] 2.2 Upgrade path: in a VM built from the previous revision (`git stash`/`HEAD~` of this change), switch to the new revision with `nixos-rebuild switch`; record whether `/usr/bin/bash` works immediately or only after reboot, confirm `/bin/sh` and `/usr/bin/env` work right after the switch and after the reboot; note the result in the README section from 1.3 if a reboot is needed

## Workflow follow-up

- Archive the change after review (`/opsx:archive`), which creates `openspec/specs/fhs-executables/spec.md`.
