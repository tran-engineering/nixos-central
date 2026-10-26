# Tasks

## 1. Shared package set and profile resolution

- [x] 1.1 Add `nixos-central-internal/lib/nixpkgs.nix` (nixpkgs `config` + `unstable` overlay, design D2) and make `modules/base/default.nix` / `modules/base/unstable.nix` use it; verify with `nix flake check` that all `host-ci-*` checks still build and `nix eval .#nixosConfigurations.ci-kde.config.system.build.toplevel.drvPath` is unchanged from before the refactor
- [x] 1.2 Move profile resolution into `lib` (name → `{ path; fallback; }`) and use it from `modules/user.nix`; verify the `host-ci-default-profile` and `host-ci-kde` drvPaths are unchanged
- [x] 1.3 Add `lib.profileNames` (D3: `_default` first, `ci-` prefixed excluded) and a comment in `users/ci-user/default.nix` documenting the `ci-` convention; verify `nix eval --json .#lib.profileNames` returns `["_default"]`

## 2. Standalone home builder

- [x] 2.1 Add `modules/home/standalone.nix` (D4: facts, `targets.genericLinux` incl. optional NVIDIA, fontconfig, user `nix.conf` with flakes, `programs.home-manager`, daily `autoUpgrade` updating only `central` with `-b backup`)
- [x] 2.2 Implement `lib.mkHome` (D1) using the shared package set and profile resolution, with a warning when a recorded profile fell back to `_default`; verify `nix eval` of a call with a nonexistent `profile` shows the warning and uses `_default`
- [x] 2.3 Add `packages.<system>.home-manager` and `templates.home` (`nixos-central-internal/templates/home/flake.nix` with `@USER@`, `@HOME@`, `@SYSTEM@`, `@PROFILE@`, `@STATE_VERSION@`, `@CENTRAL@` and an optional NVIDIA block, comment "facts only, do not change stateVersion"); verify `nix flake show` lists both and `nix run .#home-manager -- --version` reports the pinned release
- [x] 2.4 Add sample `homeConfigurations` (`ci-home-default`, `ci-home-renamed` with user `ci.user`/profile `ci-user`, `ci-home-aarch64`) and checks `home-*`, `home-profile-<name>` for every `profileNames` entry, and `home-eval-aarch64` (D8); verify `nix flake check` builds them and that `ci-home-renamed`'s `home.username` is `ci.user` and `EDITOR` is `nano`
- [x] 2.5 Verify a profile using `pkgs.unstable` builds standalone: temporarily reference `pkgs.unstable.hello` in a scratch call of `mkHome` via `nix build --impure --expr`, confirm it builds, and do not commit the scratch

## 3. Home installer script

- [x] 3.1 Create `nixos-central-internal/installer/home-only.sh` skeleton: bash guard, function-only body with `main "$@"` last, copied helpers, flag parsing for `--profile`, `--install-nix`, `--replace-existing`, `--gpu-setup`/`--no-gpu-setup` with usage on unknown flags; verify with shellcheck and that `bash home-only.sh --disk x` prints usage and writes nothing
- [x] 3.2 Implement preflight (refuse root, Linux + x86_64/aarch64, refuse NixOS with pointers to the NixOS installer and `nixos-central-upgrade`, GitHub reachability); verify by running as root (`sudo bash home-only.sh`) and with `uname` stubbed to `Darwin` via a PATH shim
- [x] 3.3 Implement Nix bootstrap (explain, confirm or `--install-nix`, official multi-user installer `--daemon --yes`, source the daemon profile, all calls via `nixx`); verify in an `ubuntu:24.04` container or VM without Nix that decline aborts without changes and accept installs Nix
- [x] 3.4 Implement profile selection (one `nix eval` of `$CENTRAL#lib` for `release` + `profileNames`, default to `$USER`'s profile else `_default`, re-prompt / abort on unknown, login-name character check); verify `--profile no-such-profile` aborts listing the profiles and the interactive default is correct for a matching and a non-matching `$USER`
- [x] 3.5 Implement NVIDIA detection and hash prefetch, writing the local flake from the template, and backing up a non-empty `~/.config/home-manager` (confirm or `--replace-existing`, named backup path); verify the generated flake for a non-NVIDIA machine evaluates with `nix eval ~/.config/home-manager#homeConfigurations.<user>.activationPackage.drvPath`
- [x] 3.6 Implement first activation (`nix run $CENTRAL#home-manager -- switch -b backup`), GPU setup offer, summary and shell-change hint; verify on a non-NixOS machine or container that a pre-existing `~/.bashrc` ends up as `~/.bashrc.backup`, the summary names the profile, and `--no-gpu-setup` prints how to run the setup later
- [x] 3.7 Document in `README.md` a section "Install on another Linux distribution" (one-liner, flags, GPU setup, NVIDIA driver updates, manual update and rollback commands, `ci-` test-profile convention) and add `shellcheck nixos-central-internal/installer/home-only.sh` to the Development commands; verify every documented command runs as written on the test machine

## 4. NixOS installer hint

- [x] 4.1 Split the live-image check out of `preflight` in `install.sh` so it runs before `ensure_root` (D6), with the `home-only.sh` one-liner in the non-NixOS message and the boot-the-image message on installed NixOS; verify with shellcheck, that running it on a non-NixOS machine prints the one-liner without a sudo prompt, and that `nix run --impure -f nixos-central-internal/tests/e2e` still passes

## 5. Publishing and CI

- [x] 5.1 Add VM test `home-installer-refuses-nixos` to `nixos-central-internal/tests` (D8); verify with `nix build .#checks.x86_64-linux.home-installer-refuses-nixos`
- [ ] 5.2 Update `.github/workflows/pages.yml` to publish `site/home-only.sh` and trigger on its path; verify after merge that `curl -sL https://tran-engineering.github.io/nixos-central/home-only.sh` returns the script and `/` still serves `install.sh`
- [ ] 5.3 Add CI job `home-installer` on `ubuntu-latest` without preinstalled Nix (shellcheck, pre-seeded `~/.bashrc`, unattended run against `git+file://$GITHUB_WORKSPACE` with `--profile ci-user --install-nix --no-gpu-setup`, assertions from D8, root refusal) and shellcheck `home-only.sh` in the existing `installer` job; verify the job passes on the PR

## 6. Integration check

- [ ] 6.1 On a real non-NixOS machine (e.g. a k-nixos standalone user), run the published one-liner with a personal profile, open a new login session, and confirm the profile's programs, GPU-accelerated graphical apps after the GPU setup, and the `home-manager-auto-upgrade.timer` being active

## Workflow follow-up

- Archive `add-gnome-and-niri-noctalia-desktops` before archiving this change; both modify `user-profiles`.
- Archive this change after review and verify the new `home-configuration` and `home-installer` main specs.
