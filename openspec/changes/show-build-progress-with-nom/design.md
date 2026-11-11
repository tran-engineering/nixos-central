# Design

## Context

- **Four build points, four tools:**
  - `install.sh` `install_system`: `nixos-install --root /mnt --flake "/mnt/etc/nixos#$HOST" ...`
  - `home-only.sh` `activate_home`: `nixx run "$CENTRAL#home-manager" -- switch --flake "$HM_DIR#$USERNAME" -b backup`
  - `modules/base/upgrade.nix`: `nixos-rebuild switch --flake "/etc/nixos#<hostname>"`, run as root after a sudo re-exec
  - `nixos-central-internal/home-upgrade`: `home-manager switch --flake "$flake" <switchFlags>`

  Neither tool lets us reliably pass `--log-format internal-json` through to its inner `nix build`.
- **The installer's log redirect.** `install_system` runs `exec > >(tee -a "$LOG") 2>&1`. From that point stdout and stderr are a pipe into the log, not the terminal. gum gets around this by drawing on `/dev/tty` (`menu()`).
- **Shared shell code.** `install.sh` and `home-only.sh` are published and run standalone (`curl | sh`), so they can't source shared files. The two upgrade scripts are built with Nix, and `upgrade.nix` already inlines a shared snippet with `builtins.readFile ./upgrade-reboot-hint.sh`.
- **Menu detection.** The installer decides once whether it can show menus (`setup_menus`):
  - `NIXOS_CENTRAL_PLAIN` is unset
  - `TERM` is not `dumb` or `unknown`
  - `/dev/tty` can be opened
  - gum is on the path, or else fetched with `nixx build --no-link --print-out-paths --inputs-from "$CENTRAL" nixpkgs#gum`
- **Tests.**
  - The e2e test (`tests/e2e/run.py`) sets `TERM=dumb` before it starts the installer and runs `nixos-central upgrade` on the installed VM.
  - `tests/default.nix` has `upgrade-failures` and other VM tests that call the upgrade scripts without a terminal.
- **Writer scripts.** `writeShellApplication` runs with `set -euo pipefail`. `install.sh` sets `-Eeuo pipefail` and an `ERR` trap (`on_error`).

## Goals / Non-Goals

**Goals:**
- A single build step that looks the same in all four places: build first, then activate.
- Exit codes, rollback and lock-file restore stay exactly as they are.
- The plain path matches today's output, so the e2e and VM tests stay valid.

**Non-Goals:**
- Showing nom in the daily systemd units.
- Changing how `nixos-install`, `nixos-rebuild` or `home-manager` activate.

## Decisions

### 1. Build first with `nix build`, then activate with the existing tool

The output of a plain `nix build` can go through nom, so each build point gets this first step:

```
nix build <installable> --out-link <tmp>/result --log-format internal-json -v 2>&1 | nom --json
```

After that step, activation runs as it does today. Everything is already in the store, so activation only evaluates the configuration again:

| Place | Installable | Activation afterwards |
|---|---|---|
| install.sh | `/mnt/etc/nixos#nixosConfigurations."$HOST".config.system.build.toplevel` with `--store /mnt --extra-substituters 'auto?trusted=1'` (as `nixos-install` builds it) | `nixos-install --root /mnt --system "$(readlink <tmp>/result)" --no-root-passwd --no-channel-copy` |
| upgrade (NixOS) | `/etc/nixos#nixosConfigurations."<hostname>".config.system.build.toplevel` | `nixos-rebuild switch --flake "/etc/nixos#<hostname>"`, unchanged |
| home-only.sh | `$HM_DIR#homeConfigurations."$USERNAME".activationPackage` | `home-manager switch --flake "$HM_DIR#$USERNAME" -b backup`, unchanged |
| upgrade (home) | `$flake#homeConfigurations."$USER".activationPackage` | `home-manager switch --flake "$flake#$USER" <switchFlags>` |

- *Why activate with the existing tool, not directly* (`switch-to-configuration` plus `nix-env --set`, or `<out>/activate`): the profile, boot-loader and backup handling of `nixos-rebuild` and `home-manager` stay untouched, and so does the existing rollback logic, which compares profile links. Evaluating twice costs seconds, while a build costs minutes.
- *Why `--system` for the installer:* `nixos-install` skips its own build when given a finished system in `/mnt`'s store. We build into that store with the same substituter setting it uses, so the live image's store is reused as before.
- *Home attribute:* the standalone upgrade now names the configuration explicitly (`#$USER`) instead of letting `home-manager` guess (`$USER@host`, then `$USER`). That way the build and the activation are guaranteed to use the same configuration. The home template only defines `homeConfigurations."@USER@"`, so homes created by the installer behave the same.
- *Build failure:* the build step fails before anything is activated. In the upgrade scripts it is part of the existing `if ! { nix flake update && build && switch; }` block, so the "profile unchanged → restore lock, 'nothing was changed'" path applies as before.
- *`--out-link` in a temp directory instead of `--print-out-paths`:* nom reads the build's stderr through the pipe, so stdout isn't free for capturing a path. The out-link also keeps the result from being garbage-collected until it is activated. The upgrade scripts already have a `mktemp` + `trap` cleanup to extend.
- *Alternative considered:* `nixos-rebuild ... |& nom`. This depends on whether `nixos-rebuild-ng` and `home-manager` pass the log format through, which differs between versions. `nh` was rejected during exploration (root check, changing CLI, and its diff/confirm step is not wanted).

### 2. One small build helper per script

A `build_with_progress <out-link> <nix build args...>` function decides between nom and plain output and runs the build.

- **Upgrade scripts:** `nixos-central-internal/lib/build-progress.sh`, inlined into both with `builtins.readFile` (the same pattern as `upgrade-reboot-hint.sh`). `pkgs.nix-output-monitor` is added to `runtimeInputs`.
- **Installers:** a copy of the function in `install.sh` and in `home-only.sh`. Both are published standalone, as with their existing `nixx` and `ask` helpers. A comment in each copy points to the other copies.

### 3. When nom is used

nom is used only when all of these hold:

- `NIXOS_CENTRAL_PLAIN` is unset
- `TERM` is not `dumb` or `unknown` (or empty)
- a terminal is available:
  - upgrade scripts and `home-only.sh`: stderr is a terminal (`[ -t 2 ]`)
  - `install.sh`: stdout and stderr are the log pipe, so the check is that `/dev/tty` can be opened, as in `setup_menus`
- the nom binary is available

Otherwise the build runs as `TERM=dumb nix build <args> --out-link <link>`. Setting `TERM=dumb` makes Nix use its line logger even on a terminal, as it already does on a serial console or a pipe. Without it, `NIXOS_CENTRAL_PLAIN` on a terminal would still get Nix's redrawing progress bar. `--log-format raw` was tried first, but it drops Nix's own messages ("building ...", errors) and still clears the line.

- *Separate from `MENUS`:* if gum can't be fetched, the installer still shows nom. The fetch is done the same way, `nixx build --no-link --print-out-paths --inputs-from "$CENTRAL" nixpkgs#nix-output-monitor`, so both use the version of the central repository's nixpkgs. If that fails, the installer prints one line saying build progress is shown as plain output.
- *Installation image:* `pkgs.nix-output-monitor` is added to `environment.systemPackages`, next to gum, so the image doesn't need to fetch it.
- *`home-only.sh`:* it runs on non-NixOS distributions where nom isn't installed, so it uses the same fetch-or-plain logic (`--inputs-from "$CENTRAL"`).

### 4. The installer: nom on the terminal, JSON in the log

Inside `install_system`, the nom path is:

```
nix build ... --log-format internal-json -v 2>&1 | tee -a "$LOG" | nom --json >/dev/tty 2>&1
```

- The raw JSON lines (`@nix {...}`) go into `$LOG`. They contain every message and the build error text, and they include no screen redraws. Converting them back into plain text would need jq on the live image, which is too much for a debugging log.
- nom draws on `/dev/tty`, as gum does, so the outer `tee` to `$LOG` never sees it.
- `on_error` still names `$LOG`. If the build fails, nom's final screen shows the error on the terminal.

The upgrade scripts and `home-only.sh` have no log file and pipe straight into `nom --json`.

### 5. Exit status

All callers run with `pipefail`, so the pipe fails when `nix build` fails, whatever nom returns. nom also exits non-zero when the build fails, but we don't rely on that. Under `install.sh`'s `set -E` the `ERR` trap fires on a failed pipe as on a failed `nixos-install` today.

## Risks / Trade-offs

- [Building with `--store /mnt` could resolve or substitute differently from `nixos-install --flake`] → Use the same `--extra-substituters 'auto?trusted=1'` and `--store /mnt`. The e2e test installs a real VM on the plain path, which runs the same build step, so it covers this.
- [Explicit `#$USER` changes which configuration is picked for a hand-edited home flake that also defines `user@host`] → Homes from the installer define only `$USER`. Mention it in the README section on standalone homes.
- [nom looks wrong on unusual terminals (the Linux console without Unicode fonts, small windows)] → `NIXOS_CENTRAL_PLAIN=1` turns it off. The installation image's console is the main case to check by hand.
- [The terminal is lost mid-build (SSH drop)] → nom gets SIGPIPE or SIGHUP. With `pipefail` the command fails, as a plain build killed by SIGHUP would.
- [Evaluating twice] → seconds per upgrade. Acceptable, see decision 1.
- [The install log is now JSON lines on the nom path] → Allowed by the spec. It is still greppable, and `jq -r 'select(.action=="msg").msg'` (after stripping `@nix `) turns it back into text.

## Migration Plan

No migration is needed. Installed machines get the new `nixos-central upgrade` with their next update. Installers fetched from the default branch use the new behavior right away. To roll back, revert the change.
