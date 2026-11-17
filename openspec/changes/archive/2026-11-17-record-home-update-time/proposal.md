# Proposal

## Why

On a standalone home, `nixos-central status` only says how long ago the last successful update was ("9 days ago"). The time itself is not shown, and the home records it only as the modification time of a stamp file, which copies, backups and restores can silently change. The user wants the home to record the exact time of its last successful update in a form that can be read back and printed. NixOS machines are not part of this change.

## What Changes

- A successful `nixos-central upgrade` on a standalone home writes the time of the update into the stamp file as an ISO 8601 timestamp with the local UTC offset (for example `2026-11-17T08:04:33+01:00`). The file's modification time is still set, so existing readers keep working.
- `nixos-central status` on a standalone home prints the absolute date and time of the last successful update next to the relative age, for example "last successful update 2026-11-17 08:04 (1 day ago)".
- When the stamp file has no readable timestamp (written by an older version, or edited by hand), the status uses the file's modification time, as today, and still prints the absolute time.
- NixOS machines keep their current behaviour and output.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `stale-update-notice`: the "Last successful update" requirement says where a standalone home records the time; the "Shown on demand" requirement says `nixos-central status` also prints the absolute time of the last successful update on standalone homes.

## Impact

- **Code:** `nixos-central-internal/home-upgrade/default.nix` (write the timestamp into the stamp instead of only touching it); `modules/home/update-notice.nix` (read the timestamp for standalone homes, print the absolute time).
- **Tests:** `nixos-central-internal/tests/default.nix` status checks for the home variant; the stamp fixture there uses `touch -d`, which must keep working through the mtime fallback.
- **Docs:** `README.md` section on `nixos-central status`, if it describes the output.
- **Users:** `$XDG_STATE_HOME/nixos-central/last-update` now has content. Nothing else reads it.
- **NixOS machines:** unaffected.
