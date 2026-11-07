# Design

## Context

See proposal.md for motivation and the specs in this change for the required behavior.

Current state that shapes the approach:

- `install.sh` runs as root on the live image, asks every question before touching the disk, writes `/etc/nixos/flake.nix` from `templates/host/flake.nix` with sed placeholders, locks it, runs disko and `nixos-install`.
- `nixos-central-private.sh` adds an overlay to an existing flake by sed edits anchored on `inputs.central.url = `, `{ central, ... }:` and `modules = [` (NixOS) / `stateVersion = ` (home), and `remove` reverses them. `--profile` is rejected on NixOS.
- `modules/base/private.nix` makes root use `/home/<user>/.ssh/id_ed25519` for `github.com` and pins GitHub's host key (`lib/github-host-key.nix`). So the key path is fixed, and the key must have no passphrase (the daily upgrade runs unattended).
- `mkHome` already has `profile ? null`, and uses one name for `profiles.resolve` and `overlay.homeModule`. `mkHost`/`hostModules` and `modules/user.nix` always use `user`.
- The e2e test serves the overlay over `git+http`, so the installer cannot assume `git+ssh` URLs.
- `add-unified-cli` (in progress) owns the current shape of `nixos-central private` and the default overlay URL; this change builds on it.

## Goals / Non-Goals

**Goals:**
- One place defines how a flake declares an overlay and a profile; the installer and `nixos-central private` use it.
- All questions, including the GitHub round-trip, happen before the disk is touched, so the long install runs unattended.
- Existing machine flakes and installs without overlay are unchanged.

**Non-Goals:**
- Adding the key to GitHub automatically (API token, `gh` device flow).
- Passphrase-protected keys, or keys for hosts other than GitHub (other SSH hosts would hit an unknown host key; `git+http(s)` URLs work without a key).
- Overlay or key setup in the standalone home installer (`home-only.sh`).
- Different profile names for the central repository and the overlay.

## Decisions

### 1. Flow position: after the secrets, before the install

```
collect_machine_facts -> select_disk -> confirm_wipe -> collect_secrets
  -> collect_private   (new: question/URL -> key -> QR -> confirm -> check -> profile)
  -> install_system    (flake + overlay edits -> lock -> disko -> nixos-install -> key)
  -> finish            (summary + overlay/profile)
```

`collect_private` comes last among the questions because the GitHub step takes the longest and needs the user's phone. After it, nothing else needs the user until the reboot question. `--profile` without `--private` is rejected in `check_flags`, before anything else happens. A `--profile` value is only checked against the overlay's profiles after the access check, which is still before disk changes.

### 2. The key lives in the live system's tmpfs until the install is done

`ssh-keygen -t ed25519 -N "" -C "<user>@<host>" -f /tmp/nixos-central-ssh/id_ed25519` (umask 077). The live root is tmpfs, so nothing persists on the USB stick. `cleanup` removes the directory after a successful install. After a failed install it stays, and the next attempt reuses the key, because the user may already have added it to GitHub. A rerun shouldn't require adding a second key. If the overlay is skipped after the key was generated, the key is still installed. The user may already have added it to GitHub, and a later `nixos-central private setup` then works without further steps.

*Alternative:* generate the key on first boot and show it there. Rejected: it moves the GitHub step back after installation, which is what this change removes.

### 3. QR code via `qrencode` from the central repository's nixpkgs

`nixx run --inputs-from "$CENTRAL" nixpkgs#qrencode -- -t ansiutf8 -m 2 <<<"$pubkey"`. `--inputs-from` uses the nixpkgs revision locked by the central repository. Its source is already fetched by `preflight`'s `lib` evaluation, so this costs one binary-cache download instead of a second nixpkgs tarball. `ansiutf8` packs two rows into one character with half-blocks: a key line of about 100 bytes needs about 41 columns and 21 rows. Plain `ansi` would need about 90 columns and wrap on an 80-column console. If `qrencode` can't be fetched, the installer prints only the text key and says so. The QR code is a convenience, not a requirement for continuing.

### 4. SSH for the overlay in the live system via root's `~/.ssh/config`

Before the access check, the installer writes `/root/.ssh/known_hosts` with GitHub's pinned host key, plus a `/root/.ssh/config` block `Host github.com / IdentityFile /tmp/nixos-central-ssh/id_ed25519 / IdentitiesOnly yes`. It mirrors what `modules/base/private.nix` does on the installed system. Every later fetch then uses the key: the access check, `nix flake lock`, disko's and `nixos-install`'s evaluation. This holds regardless of whether Nix fetches through the `git` CLI or libgit2. The GitHub host key comes from a new `lib.githubHostKey` export (from `lib/github-host-key.nix`), so the installer doesn't duplicate it.

*Alternative:* `GIT_SSH_COMMAND` in the environment. Rejected: it only applies when Nix shells out to `git`, and every Nix invocation would have to carry it.

### 5. Access check and profile list

Access: `nixx flake metadata --refresh "$url"`, the same check `nixos-central private setup` does. On failure the installer shows the error and asks `[r]etry / [s]kip overlay`. Profiles: `nixx eval --json "$url#homeModules" --apply builtins.attrNames`. If the overlay has no `homeModules`, the installer reports it as not a valid overlay, with the same retry/skip choice. The default answer is the username if it is listed, otherwise `default` if listed, otherwise no default.

### 6. One flake-edit library shared by the installer and `nixos-central private`

The sed edits move from `nixos-central-private.sh` into `nixos-central-internal/private/flake-edit.sh`. It defines `flake_add_overlay <flake> <mode> <url> [profile]` and `flake_remove_overlay <flake> <mode>`, including the anchor checks. The private package concatenates it in front of the script, as it does with `GITHUB_HOST_KEY`. `lib.privateFlakeEdit` exports its path. The installer gets it with `nixx eval --raw "$CENTRAL#lib.privateFlakeEdit"` and sources it after `write_machine_flake` has rendered the unchanged template, before `nix flake lock`. So an installed flake has exactly the shape that `setup` writes and `remove` expects.

On NixOS, the profile line is inserted after the `user = "...";` line as `profile = "<name>"; # in the central repository or the private overlay`. On NixOS, `flake_remove_overlay` also deletes a `profile = ` line. On standalone homes the template always has a `profile` line, which `setup` rewrites and `remove` leaves alone, as today.

*Alternative:* optional `@PRIVATE@`/`@PROFILE@` blocks in `templates/host/flake.nix`. Rejected: that defines the flake shape a second time, and both definitions would drift apart.

### 7. `mkHost` profile: a module option, resolved like `mkHome`

`hostModules` takes `profile ? null` and sets `nixos-central.profile` (new option in `modules/options.nix`, `nullOr str`, default `null`). `modules/user.nix` and the overlay import in `hostModules` use `name = if profile == null then user else profile`. Account name, home directory and password file stay keyed by `user`. Like `mkHome`, a recorded profile that exists in neither the central repository nor the overlay produces a warning that lists the available profiles. The build still succeeds with `_default`.

### 8. Key installed after `nixos-install`, owned via `nixos-enter`

The primary user only exists after the new system's activation. After `nixos-install`, the installer copies both key files to `/mnt/home/<user>/.ssh/` (0700 directory, 0600 private key, 0644 public key). It then runs `nixos-enter --root /mnt -c 'chown -R <user>:users /home/<user>/.ssh'`. `nixos-enter` runs the activation, which creates the user, so the name resolves. `nixos-install` itself never needs the key in the user's home: its fetches run in the live system (decision 4).

## Risks / Trade-offs

- [Half-block characters may not render on the live console font] → Check in the e2e VM on the VGA console (screenshot). If they don't render, fall back to `-t ansi -m 1`, and check that it fits within 80 columns for a typical key line.
- [`nixos-enter` activation in the installer might fail or have side effects] → It runs at the very end, inside the existing ERR trap. If it fails, the step name is reported and the system is otherwise installed. The e2e check verifies the key's owner and mode.
- [The user adds the key as a deploy key or to the wrong account] → The access check catches it before the install, and the retry option allows fixing it without restarting.
- [A passphrase-less key on the disk] → Same as the existing post-install path; the disk is LUKS-encrypted. Documented in the README.
- [The installer runs code fetched from the central repository (`flake-edit.sh`)] → It already does (templates, disko, the whole system). The path comes from the same locked `$CENTRAL`.
- [Existing e2e runs get one more prompt] → Updated in the same change. Runs that pass all flags still see the question unless `--private` is given. Every install already needs a terminal for the passphrase.

## Migration Plan

No migration. Machine flakes without `profile` and without overlay build as before. Machines installed with an overlay look the same as machines where `nixos-central private setup` was run. Rollback means reverting the commit. Machine flakes with a recorded `profile` would then fail to evaluate against an older central (unknown argument), so this applies only to machines installed with this change.

## Open Questions

- Should the installer also show a QR code for `https://github.com/settings/ssh/new`, or is the text hint enough? This can be decided during implementation once the screen layout is visible.
