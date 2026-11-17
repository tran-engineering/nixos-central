# Design

## Context

`nixos-central-internal/home-upgrade/default.nix` already runs `touch "$stamp"` after a successful upgrade, and `modules/home/update-notice.nix` reads that file's modification time as the last successful update. Only the relative age is printed. The `stamp` path is `$XDG_STATE_HOME/nixos-central/last-update` on standalone homes (`config.nixos-central.updateNotice.stamp`).

## Goals / Non-Goals

**Goals**
- The standalone home stores the exact completion time in the stamp file's content, so it can be read and printed without relying on mtime alone.
- `nixos-central status` on a standalone home prints the absolute local time next to the age.

**Non-Goals**
- No change on NixOS (`/var/lib/nixos-central/last-update` stays a bare touch, and its output is unchanged).
- No new file, option or subcommand. The existing stamp file carries the time.
- No change to which events count as a successful update.

## Decisions

1. **Content of the stamp file.** `home-upgrade` writes `date -Iseconds` (for example `2026-11-17T08:04:33+01:00`) to the stamp, then sets its mtime to the same moment with `touch -d`. Writing the content first and deriving the mtime from it keeps both in agreement. The timestamp is written to a temporary file and moved into place, so a crash cannot leave a half-written file.
   *Alternative:* a second file next to the stamp. Rejected: two files can disagree, and the stamp already is the record.

2. **Reading the time.** In `update-notice.nix`, the standalone branch reads the stamp's first line and converts it with `date -d` into epoch seconds. If that fails (old or hand-edited file), it falls back to the mtime, as today. The epoch value feeds the same `last` variable, so the age logic does not change. NixOS takes the mtime path only.
   *Why prefer the content:* a copy or restore that preserves no mtime keeps the time; the mtime is still used when the content is missing.

3. **Output.** When the time is known, the status line becomes `nixos-central: last successful update <YYYY-MM-DD HH:MM> (<age>, ...)`. The date format is `date -d @<epoch> '+%Y-%m-%d %H:%M'` in local time. The age text stays as it is. Staying on the existing line keeps the shell notice's shape.

4. **Gating.** The shared script branches on `cfg.standalone` the same way it already does for the lock and profile paths. The time-printing and content-reading code exists only in the standalone branch.

## Risks / Trade-offs

- `date -d` parsing of an ISO string differs between GNU coreutils versions. It is available in the pinned nixpkgs, and the fallback covers any failure. → The test checks parsing with a fixed timestamp.
- Writing the stamp content adds a process to every upgrade. Negligible.
- The notice runs in every new shell. The extra `date` call only runs when the stamp exists, and it must not print errors (the spec's "never disturbs the shell" rule). Errors go to `/dev/null`.

## Migration Plan

Nothing to migrate. Existing stamp files (mtime only) keep working through the fallback. The next successful upgrade rewrites the file with content.
