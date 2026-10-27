# Design

## Context

- Every profile already gets `modules/home/shell.nix` and `modules/home/private.nix`: on NixOS through `home-manager.sharedModules` in `modules/user.nix`, standalone through the module list in `lib.mkHome`. Only `standalone.nix` distinguishes the two.
- The login shell comes from `nixos-central.shell`; `shell.nix` enables the matching home-manager program. Other shells may be enabled too (the default profile enables bash).
- NixOS: the daily `nixos-upgrade` service (nixpkgs `system.autoUpgrade`, a oneshot with `script`) runs `boot`, so `/nix/var/nix/profiles/system` can be ahead of `/run/current-system`. `reboot-notify.nix` already compares these paths. `nixos-central-try` activates a system that is in no profile.
- Standalone: the daily user service `home-manager-auto-upgrade` updates `~/.config/home-manager/flake.lock` and switches; generations live in `$XDG_STATE_HOME/nix/profiles/home-manager-*-link` (older Nix: `/nix/var/nix/profiles/per-user/$USER/`).
- Nix creates no new generation when a rebuild yields the same result, and the central repository can be quiet for more than a week (lock updates are weekly PRs). Neither generation age nor commit age alone tells whether updates still work; hence a recorded "last successful update".
- Store paths have mtime 1; generation links keep their creation time.

## Goals / Non-Goals

**Goals:**
- One small script, the same for bash, fish and zsh, cheap enough to run at every interactive shell start.
- No change to closures when only the central commit date changes.

**Non-Goals:**
- Notifying root shells or users other than the profile's user.
- Desktop notifications (reboot-notify covers the staged case).
- Diagnosing why an upgrade failed; the hint points at the place to look.

## Decisions

**Recording successful updates in a stamp file** (its mtime is the time):
- NixOS: `/var/lib/nixos-central/last-update`, touched by `systemd.services.nixos-upgrade.postStart` in `modules/base/auto-upgrade.nix` (ExecStartPost of a oneshot runs only after ExecStart succeeded) and at the end of a successful `nixos-central-upgrade`. Root's umask makes it world-readable.
- Standalone: `${config.xdg.stateHome}/nixos-central/last-update`, touched by `ExecStartPost` added to `systemd.user.services.home-manager-auto-upgrade` in `standalone.nix`.
Alternative: ask systemd for the last successful run (`ExecMainExitTimestamp`) — rejected: forgotten after reboot and a failed run overwrites it.

**Last successful update** = the later of the stamp's mtime and the newest generation's install time (lstat mtime of the link the profile points to). The generation part covers manual rebuilds, `home-manager switch` and fresh installs before the first stamped run. Missing both → unknown → no notice.

**Shared home module `modules/home/update-notice.nix`, added next to `shell.nix`.** It must reach every profile, including `_default`, so it goes into the same two lists as `shell.nix` rather than being an opt-in shared module. Alternative: NixOS `environment.interactiveShellInit` — rejected: doesn't cover standalone homes, and the user's fish config comes from home-manager.

**Options** (`nixos-central.updateNotice`):
- `days` (int, default 7; `0` turns it off) — set by profiles.
- `standalone` (bool, internal, default false) — set to true by `standalone.nix`. Selects the stamp, profile and lock file paths and the hint.

**Script `nixos-central-update-notice`** (`writeShellApplication`, coreutils + jq). Paths, threshold and mode are baked in as defaults of environment variables (`NIXOS_CENTRAL_NOTICE_*`), which only tests override, together with "now". It is called from `programs.bash.initExtra`, `programs.fish.interactiveShellInit` and `programs.zsh.initContent` (all interactive-only) of whichever shells are enabled, only when `days > 0`, with stderr discarded and failures ignored.

**Running configuration's age** = lstat mtime of the generation link whose target equals the running configuration (NixOS: `/run/current-system`; standalone: the active `home-manager` profile). No match (tried branch) → left out.

**Central revision age** = `nodes.central.locked.lastModified` from `/etc/nixos/flake.lock` or `~/.config/home-manager/flake.lock`, read at runtime. Alternative: bake `inputs.self.lastModified` into the configuration — rejected: every central commit would create a new boot generation, pushing older ones out of the 10-entry boot menu.

**Staged check** (NixOS): the system profile differs from both `/run/booted-system` and `/run/current-system`, as in `reboot-notify.nix`.

**Output**, e.g.:
```
nixos-central: last successful update 9 days ago (running system from 15 days ago, central revision from 16 days ago).
An update is installed; reboot to use it.                                   # staged
Run nixos-central-upgrade to update now (log: journalctl -u nixos-upgrade).  # NixOS
Check: systemctl --user status home-manager-auto-upgrade                    # standalone
```
Whole days rounded down; "today", "1 day", "N days".

## Risks / Trade-offs

- [Shell start cost] → coreutils + one `jq` call and a glob over a few dozen links; no network.
- [Existing machines have no stamp right after this ships] → the generation time is used until the next successful daily run.
- [Clock wrong] → ages may be off; harmless, only a notice.
- [Notice repeats in every new terminal while stale] → intended; profiles can raise the threshold or turn it off.

## Migration Plan

Ships with the next daily upgrade; nothing to migrate. Turning it off: `nixos-central.updateNotice.days = 0;` in the profile.
