# Tasks

## 1. Record the time on standalone homes

- [x] 1.1 In `nixos-central-internal/home-upgrade/default.nix`, replace the bare `touch "$stamp"` with: write `date -Iseconds` to a temporary file next to the stamp, move it over the stamp, then `touch -d` the stamp to the same time. Keep the `mkdir -p` and the comment about the update notice.
- [x] 1.2 Check that the success path still prints "The latest update is active." and that a failed upgrade writes no stamp (the existing early exit covers it).

## 2. Show the time in the notice

- [x] 2.1 In `modules/home/update-notice.nix`, in the standalone branch only, read the stamp's first line and convert it to epoch seconds with `date -d`. If that fails, keep the mtime value.
- [x] 2.2 In the same branch, when the last update is known, print `last successful update <YYYY-MM-DD HH:MM>` before the age in parentheses. Leave the NixOS line and the `--if-stale` decision unchanged. Redirect any `date` error to `/dev/null`.
- [x] 2.3 Update the comment at the top of the file to say where a standalone home records the time.

## 3. Tests

- [x] 3.1 In `nixos-central-internal/tests/default.nix`, extend the standalone status check: a stamp with a fixed ISO timestamp two days back prints that date and time and "2 days ago".
- [x] 3.2 Keep a case with a stamp that holds no timestamp (plain file, set by `touch -d`); it prints the mtime date and time.
- [ ] 3.3 Run the relevant checks with `nix build .#checks.x86_64-linux.<name>` (the home status check). Note that local VM tests fall back to TCG here and may time out; if so, report that they were not run rather than claiming a pass.

## 4. Docs

- [x] 4.1 In `README.md`, update the `nixos-central status` description in the places that describe its output (around lines 191 and 696) to mention the time on standalone homes.

## 5. Verify

- [x] 5.1 `openspec validate record-home-update-time` passes.
- [ ] 5.2 Run `nix flake check` or the affected checks, and report results with output.
