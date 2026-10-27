# Tasks

## 1. Builder arguments

- [x] 1.1 Add `private ? null` to `mkHost` and `mkHome`: import `private.homeModules.default` for the primary user (and `private.nixosModules.default` on NixOS if exported), set `nixos-central.private.enable`, and throw on overlays with inputs; verify the drvPaths of all `ci-*` hosts and homes are unchanged, and that a test overlay (a module-only flake under `nixos-central-internal/tests/`) adds its file to a scratch host and a scratch home
- [x] 1.2 Pass `centralModules` (all shared home modules in `modules/home/` by name, excluding `standalone.nix` and `shell.nix`) as a special argument in `mkHost` (home-manager `extraSpecialArgs`) and `mkHome`; add a check that the attrset matches the directory; verify a test overlay importing `centralModules.fish` evaluates on a scratch host and home
- [x] 1.3 Add an eval check with a test overlay that declares an input; verify evaluation fails with the "overlays must not have inputs" message

## 2. Personal profile out of central

- [x] 2.1 Replace `users/kt` with `users/ci-modules` (imports `../_default` and every module via `centralModules`, selects fish); in `flake.nix` rename `host-eval-kt` to `host-eval-ci-modules` and `ci-home-kt-aarch64` to `ci-home-modules-aarch64`, and add an x86_64 eval-only home check for `ci-modules`; verify `nix eval --json .#lib.profileNames` is `["_default"]` and `nix flake check` passes
- [x] 2.2 Update the README: personal settings belong in a private overlay; the "Shared modules" example shows an overlay using `centralModules` next to the in-repo import form; the Development section lists the renamed checks; verify no README text still refers to `users/kt`

## 3. Upgrades and fetching

- [x] 3.1 Add GitHub's Ed25519 host key (cross-checked with `https://api.github.com/meta`) as `programs.ssh.knownHosts."github.com"` and the root-only `Match host github.com localuser root` identity block for `/home/<user>/.ssh/id_ed25519`; verify `/etc/ssh/ssh_config` and `ssh_known_hosts` in a built host contain both
- [x] 3.2 Make `central-update-flags.nix` depend on `nixos-central.private.enable` (also `--update-input private`) for the auto-upgrade and `nixos-central-upgrade`, and the standalone home's `preSwitchCommands`; verify the generated unit and the upgrade script for a host with and without overlay
- [x] 3.3 Offline VM test (stub `central` that uses the overlay, then throws, like `upgrade-failures`): a new overlay commit is picked up by `nixos-central-upgrade` ("Updated input 'private'"); with the overlay unreachable, both `nixos-central-upgrade` and `nixos-upgrade.service` fail, and `flake.lock` and the system profile are unchanged; as root, `ssh -G github.com` uses `/home/alice/.ssh/id_ed25519`

## 4. Setup command

- [x] 4.1 Add `nixos-central-private` (`setup <url>`, `remove`) per the design: mode detection, sudo re-exec on NixOS, known_hosts on standalone, `nix flake metadata --refresh` access check, anchored edits of the template shape with backup and restore, activation; available on NixOS hosts and standalone homes; verify with shellcheck
- [x] 4.2 Offline VM test: `setup` with an unreachable URL fails with the key hint and leaves `/etc/nixos` unchanged. e2e test (real builds): the test server also serves the test overlay; on the installed machine, `setup` adds the input, `inherit private;` and the overlay's file; a new overlay commit plus `nixos-central-upgrade` activates it; `remove` takes it out again
- [x] 4.3 Standalone test (in the existing `home-installer` CI job or a scratch home): `setup` with a `git+file` overlay adds it to `~/.config/home-manager/flake.nix`, the file appears, and `preSwitchCommands` include `private`

## 5. Documentation

- [x] 5.1 README: a "Private overlay" section (what belongs there, the overlay flake shape with an example `flake.nix` without inputs, the after-first-boot steps: copy `~/.ssh/id_ed25519`, run `nixos-central-private setup git+ssh://git@github.com/<you>/<repo>`, what happens when access breaks, `remove`), and update "Users and profiles" for the relaxed customization rule; verify the example overlay flake builds with `mkHome` in a scratch evaluation

## 6. Profiles in overlays

- [x] 6.1 Resolve the overlay profile in `mkHost` (user) and `mkHome` (profile fact, else user): `homeModules.<name>`, else `homeModules.default`, else throw listing the overlay's profiles; `mkHome` warns about a missing profile only if neither central nor the overlay has it; verify with eval checks for: profile match, fallback to `default`, no match (fails), standalone overlay-only profile without warning
- [x] 6.2 Add `--profile NAME` to `nixos-central-private setup` (standalone only; rewrites the `profile = "...";` line; refused on NixOS); verify with the stub test of the editing logic, and extend the CI `home-installer` step to set up the test overlay with `--profile` and check that profile's file
- [x] 6.3 Update the README "Private overlay" section (profiles per user, `users/<name>` layout, fallback and failure, `--profile` on standalone homes); verify the example overlay flake evaluates with `mkHome`

## Workflow follow-up

- Create the private repository (e.g. `KeeTraxx/kt-private`) with `homeModules.default` holding the former `users/kt` (module selection via `centralModules`, fish, fonts, terminal themes, `ls = eza`) plus the rest from k-nixos: git/jj identity, swisstopo SSH config and scripts, personal apps, dotfiles. Then run the setup on each machine.
- plasma-manager: kt's KDE settings need its home module, which an overlay can't bring itself. Add it to central (input + module for every profile) in a separate change before moving the plasma config.
- Possible follow-up change: desktop notification when the daily upgrade fails.
