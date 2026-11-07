# Design

## Context

Today, `nixos-central-internal/lib/profiles.nix` resolves a name to `users/<name>`, or to `users/_default` if that directory doesn't exist. It also lists the selectable profiles (`lib.profileNames`), which `home-only.sh` and the `home-profile-<name>` checks consume. `modules/user.nix` (NixOS) and `mkHome` (standalone) import the resolved path. The private overlay module comes on top (`overlay.homeModule`), selected by the same name. Both builders warn when a recorded profile exists neither centrally nor in the overlay.

There are no personal profiles left in `users/` (see proposal.md, "Why"). So in practice the resolution always ends at `_default`, apart from the two CI profiles.

`mkHost` and `mkHome` are the only interface that machine and home flakes depend on (comments in `lib/default.nix`), so their arguments must keep working. Deployed home flakes contain `profile = "<something>";`, usually `"_default"` or a name that only exists in the overlay.

This change builds on `add-private-overlay-at-install` (the `profile` argument of `mkHost`, `flake-edit.sh`, the installer's overlay step). That change has to be archived first.

## Goals / Non-Goals

**Goals:**
- One unconditional base home module. No name-based lookup in the central repository.
- Test profiles that never appear in anything a user can select or record.
- Existing machine and home flakes build unchanged. They warn only where a recorded profile has no effect.

**Non-Goals:**
- An overlay step in `home-only.sh`.
- Changing how the overlay profile is selected (name, then `default`, else fail).
- Changing the content of the base configuration, other than making its settings defaults.

## Decisions

### 1. `users/_default` becomes `modules/home/base.nix`, internal

The base module is imported unconditionally, next to the other internal home modules (`shell.nix`, `private.nix`, `command.nix`, `update-notice.nix`, `gc.nix`). On NixOS it goes into `home-manager.sharedModules` in `modules/user.nix`. In `mkHome` it replaces `resolved.path`. `base.nix` is added to the `internal` list in `lib/overlay.nix`, so it does not become a `centralModules` entry, and the `central-modules` check keeps its expected list.

The scalar settings are `lib.mkDefault`: `programs.bash.enable`, `programs.git.enable`, `init.defaultBranch`, `programs.firefox.enable`, `EDITOR`. `home.packages` merges as a list anyway. An overlay can then write `EDITOR = "nano"` without `mkForce`. Overlays that already use `mkForce` keep working.

*Alternative*: keep a "default profile" that overlays could replace instead of extend. Rejected: overlays are always applied on top today, and replacing would need an opt-out mechanism nobody asked for. If an overlay needs to remove a package from the base, that can be added later as an option.

*Alternative*: name it `default-profile.nix`. Rejected: it is no longer a profile, and "default" collides with the overlay's `homeModules.default`.

### 2. Test profiles are injected through internal builders, not through a public argument

`ci-user` and `ci-modules` move to `nixos-central-internal/tests/profiles/<name>/default.nix` and drop their `imports = [ ../_default ]`, because the base is always present. `ci-user` keeps only `EDITOR = "nano"` (now without `mkForce`, which also tests decision 1). `ci-modules` keeps `centralModules`, fish and the Plasma setting.

Injection:
- **NixOS**: `ciHost` passes `modules = [ { home-manager.users.<user>.imports = [ profile ]; } ]`. That is the existing public `modules` argument, already used for `ci-hardware.nix`.
- **Standalone**: `lib/default.nix` gets an internal `homeModules`-style helper (`homeConfigModules args`), analogous to the existing `hostModules`. It returns the module list that `mkHome` passes to `homeManagerConfiguration`. `ciHome` calls `homeManagerConfiguration` with that list plus the test profile. `mkHome` keeps its signature.

*Alternative*: serve the test profiles as homeModules of the test overlay (`tests/overlay`). Rejected: that would set `nixos-central.private.enable` on every CI configuration and change their upgrade services. The point of `ci-kde` and the others is to test machines without an overlay.

*Alternative*: an optional `modules` argument for `mkHome`. Rejected: it would add a public customization layer to standalone homes, which `user-profiles` ("Customization happens in the private overlay") forbids.

### 3. The recorded profile only selects the overlay profile

`lib/profiles.nix` and `lib.profileNames` are removed. In both builders, `name = if profile == null then user else profile` is used only for `overlay.homeModule`. Warnings:

| Situation | Behavior |
|---|---|
| `profile` set, no overlay, `profile != "_default"` | warning: "profile X has no effect without a private overlay" |
| `profile = "_default"`, with or without overlay | treated as no recorded profile: nothing (homes from the old installer; with an overlay, the overlay's `_default` or `default` profile is used, without a warning) |
| `profile` set, overlay without `X` but with `default` | warning: "the private overlay has no profile X; using its default profile" (as `mkHome` does today, now also on NixOS) |
| no `profile`, overlay without `<user>` but with `default` | nothing (as today) |
| overlay without `X` and without `default` | throw from `overlay.homeModule` (as today) |

The NixOS warning text names `/etc/nixos/flake.nix`, the standalone one names `~/.config/home-manager/flake.nix`. Both list the overlay's profiles if there is an overlay.

### 4. `home-only.sh` drops the profile step; the home template has no profile line

`preflight` no longer evaluates `profileNames`, only `release`. `choose_profile`, `valid_profile`, `PROFILES` and the `@PROFILE@`/`@PROFILES@` placeholders go away. `--profile` stays in `parse_flags`, but only to abort with "Profiles come from a private overlay: after installing, run `nixos-central private setup [<url>] --profile NAME`." That gives a clear message instead of "unknown flag" for people who copy the old README line. The summary drops the profile line and adds the setup hint.

`flake-edit.sh` then treats both modes the same way:
- **add with profile**: rewrite an existing `profile = "…";` line, or else insert one after `user = "…";` (both templates have a `user` line).
- **remove**: delete the `profile` line in both modes.

The anchor check follows the same rule.

On remove for old homes: `flake_remove_overlay home` deleting a `profile = "_default";` line is harmless, because without an overlay the line had no effect. A home whose profile came from the old template and was never touched by `private setup` keeps the line until the user removes it. The line only warns if it isn't `_default`.

*Alternative*: keep `--profile` in `home-only.sh` and record it unvalidated for a later `private setup`. Rejected: it would record a profile without an overlay, which warns on every build.

### 5. CI and tests

- `flake.nix`: drop `ci-default-profile` (identical to `ci-none` now) and the `home-profile-<name>` loop. Keep `ci-home-default` (now "no profile, no overlay", without the `profile` argument). Rename `ci-home-renamed` to `ci-home-dotted` (`user = "ci.user"` with the `ci-user` test profile). It no longer tests a profile/login-name mismatch; `overlay-profiles` covers that.
- `host-profile` check: (a) `profile = "ci-overlay"` with the test overlay: overlay file present, `EDITOR == "vim"`, no warning. (b) `profile = "kt"` without overlay: base, warning "no effect". (c) no profile: base, no warning. (d) `profile = "nosuch"` with the test overlay: overlay default, warning.
- `overlay-profiles`: keep the assertions and add "`_default` without overlay: no warning".
- `private-flake-edit`: the home template now has no profile line. Add with profile inserts it after `user`, and remove deletes it (byte-identical round trip, as for NixOS).
- `.github/workflows/ci.yml`: `home-only.sh --install-nix --no-gpu-setup` without `--profile`. The checks stay `EDITOR=vim`, and the absence of `profile =` in the flake replaces the grep for `profile = "_default"`. A further step asserts that `--profile x` exits non-zero and names `nixos-central private setup`.
- e2e `run.py`: the `try`/`upgrade`/auto-upgrade steps write to `modules/home/base.nix` of the served repo copy instead of `users/alice/default.nix`: the original content plus `home.sessionVariables.EDITOR = lib.mkForce "nano";` and the marker files, inserted before the closing brace. The assertion texts change from "personal profile users/alice" to "central base change".

## Risks / Trade-offs

- [An existing overlay sets an option that the base now sets with `mkDefault`] → it wins now, where it previously conflicted or needed `mkForce`. That only relaxes things; no build that worked before breaks.
- [Existing homes with `profile = "kt"` and no overlay start warning] → this is intended; the warning says how to fix it (add the overlay or delete the line). The build still succeeds.
- [External docs or scripts call `home-only.sh --profile`] → explicit abort with the replacement command, before any file is written.
- [`lib.profileNames` used by a fork's tooling] → there are no known consumers. The removal is announced as breaking in the proposal and the README.
- [Conflict with the in-flight `add-private-overlay-at-install` deltas] → archive that change first. This change's deltas were written against its result.

## Migration Plan

1. Archive `add-private-overlay-at-install` (its remaining manual tasks 3.6 and 4.2 don't touch profiles).
2. Implement this change in one PR. Machines and homes pick it up with their normal daily update, and nothing has to be edited locally.
3. Rollback: revert the PR. Deployed flakes never referenced `users/`, so a revert restores the old behavior on the next update.
