# Design

## Context

- Profiles (`users/<name>/default.nix`) are plain home-manager modules, reached only through `modules/user.nix` inside `lib.mkHost`. There they get `pkgs` from the NixOS instance (`useGlobalPkgs`: `allowUnfree` from `modules/base/default.nix`, `pkgs.unstable` from `modules/base/unstable.nix`) and `home.stateVersion` from `system.stateVersion`. Profile resolution (`users/<user>` else `users/_default`) lives inline in `modules/user.nix`.
- `install.sh` is ~420 lines of function definitions with `main` on the last line; it calls `ensure_root` (re-exec under sudo) before `preflight`, which is where the live-image check lives. Pages publishes it via `.github/workflows/pages.yml`.
- The pinned home-manager (release-26.05) provides `targets.genericLinux` (GPU integration on by default, one-time `non-nixos-gpu-setup` as root, NVIDIA via `gpu.nvidia.{enable,version,sha256}`) and `services.home-manager.autoUpgrade` (`useFlake`, `flakeDir` defaulting to `~/.config/home-manager`, `preSwitchCommands`, user timer with `Persistent = true`). For stateVersion ≥ 26.05, `preSwitchCommands` defaults to `[ ]`, i.e. the lock is not updated unless configured.
- k-nixos's `home-manager-only/` is the prior art: a separate flake and lock, a custom nixGL wrapper, and `HOME_MANAGER_BACKUP_EXT` for existing dotfiles.

## Goals / Non-Goals

**Goals:**
- One code path for package set and profile resolution, used by `mkHost` and `mkHome`, so NixOS and standalone homes cannot diverge.
- `home-only.sh` that is fully scriptable via flags, so CI can run it unattended.

**Non-Goals:**
- macOS / nix-darwin, non-Linux, 32-bit.
- Changing the login shell, managing system services, or anything requiring root beyond the Nix install and the GPU setup.
- A standalone counterpart of `nixos-central-try` / `nixos-central-upgrade` (see Open Questions).
- Changing `mkHost`'s interface or NixOS behaviour.

## Decisions

### D1 `lib.mkHome` interface
```nix
central.lib.mkHome {
  user = "khoi.tran";               # login name -> home.username
  homeDirectory = "/home/khoi.tran";
  stateVersion = "26.05";           # do not change
  system = "x86_64-linux";          # or aarch64-linux
  profile = "kt";                   # optional, defaults to user
  nvidia = { version = "..."; sha256 = "sha256-..."; };  # optional
}
```
Returns `home-manager.lib.homeManagerConfiguration`. The local flake exposes it as `homeConfigurations."<user>"`, because `home-manager switch --flake <dir>` (used by the installer and by auto-upgrade) looks up `$USER@$(hostname)` then `$USER`. `homeDirectory` is recorded rather than derived, since it is a fact of the machine (`$HOME`).

*Alternative:* central `homeConfigurations.<name>` per profile (`home-manager switch --flake github:…#kt`). Rejected: stateVersion and home directory would be central, so bumping them silently changes existing homes, and users without a profile get nothing.

### D2 Shared package set and profile resolution
New `nixos-central-internal/lib/nixpkgs.nix` defines the nixpkgs `config` (`allowUnfree`) and the `unstable` overlay once. NixOS keeps setting them through the module system (`modules/base` imports from the shared file); `mkHome` uses `import nixpkgs { system; config; overlays; }`. Profile resolution moves into `lib` as a function from profile name to `{ path; fallback; }`; `modules/user.nix` and `mkHome` both call it. `mkHome` adds a `warnings` entry when an explicitly recorded profile fell back to `_default`.

### D3 Selectable profiles
`lib.profileNames` = directories in `users/` whose names do not start with `ci-` (test-only convention; `ci-user` is today's only one). `_default` is included and listed first.

### D4 Standalone home module (`modules/home/standalone.nix`)
Added by `mkHome` next to the profile:
- `home.username`, `home.homeDirectory`, `home.stateVersion` from the facts.
- `targets.genericLinux.enable = true`; `gpu.nvidia` from `nvidia` when set.
- `fonts.fontconfig.enable = true`.
- `nix.package = pkgs.nix` and `nix.settings.experimental-features = [ "nix-command" "flakes" ]`, so `~/.config/nix/nix.conf` enables flakes for the user (the official installer does not).
- `programs.home-manager.enable = true` (CLI for manual switch and rollback).
- `services.home-manager.autoUpgrade`: `enable`, `frequency = "daily"`, `useFlake = true`, `preSwitchCommands = [ "nix flake update central" ]` (only the `central` input, like `central-update-flags.nix`), `flags = [ "-b" "backup" ]`.

A failed build leaves the active generation untouched (home-manager only activates after a successful build). The lock may already be updated by then; the next run retries.

### D5 `home-only.sh`
Same skeleton as `install.sh` (bash guard, functions only, `main "$@"` last, `NIXOS_CENTRAL_FLAKE` override); helpers (`info`, `die`, `ask`, `require_tty`, `nixx`) copied, not shared, because a piped script cannot source files. Flags:

| Flag | Meaning |
|---|---|
| `--profile NAME` | skip profile prompt |
| `--install-nix` | consent to install Nix if missing |
| `--replace-existing` | consent to back up an existing `~/.config/home-manager` |
| `--gpu-setup` / `--no-gpu-setup` | answer the GPU setup question |

Flow: refuse root → check Linux + `x86_64`/`aarch64` → refuse NixOS (`/etc/NIXOS`) → network → Nix (if missing: explain, confirm, run the official multi-user installer `--daemon --yes`, then source `nix-daemon.sh`) → fetch `release` and `profileNames` with one `nix eval` of `$CENTRAL#lib` → choose profile → login name check (portable characters `[A-Za-z0-9._-]`, else abort) → NVIDIA detection (`/proc/driver/nvidia/version` → version; `nix store prefetch-file --json` of the driver URL → hash) → back up an existing `~/.config/home-manager` to `~/.config/home-manager.backup-<timestamp>` after confirmation → write the local flake from `templates/home/flake.nix` (same placeholder substitution as `write_machine_flake`) → `nix run $CENTRAL#home-manager -- switch --flake ~/.config/home-manager -b backup` → offer `sudo non-nixos-gpu-setup` from the new generation → summary, plus a shell-change hint when the profile provides a shell (e.g. fish) other than `$SHELL`.

*Alternative:* the official vs. Determinate Nix installer. Determinate enables flakes by default, but now installs its own Nix distribution; the official installer plus the user-level `nix.conf` from D4 keeps upstream Nix.

### D6 `install.sh` change
Split the live-image test out of `preflight` into a check that runs before `ensure_root`, so a user on Ubuntu gets no sudo prompt. Without `/etc/NIXOS` the message includes the `home-only.sh` one-liner; on installed NixOS (no tmpfs/overlay root) it keeps telling the user to boot the image.

### D7 Central flake outputs
- `templates.home` (`nixos-central-internal/templates/home`).
- `packages.<system>.home-manager` = the pinned home-manager input's package, so the first switch runs the version the config was evaluated with.
- `homeConfigurations` samples (not meant to be installed): `ci-home-default` (`_default`), `ci-home-renamed` (user `ci.user`, profile `ci-user`), `ci-home-aarch64` (`_default` on `aarch64-linux`).
- `systems` gains `aarch64-linux` only where needed for the sample; checks stay on `x86_64-linux`.

### D8 Tests and CI
- `checks.x86_64-linux`: `home-<name>` = activation package of every x86_64 sample, plus `home-profile-<name>` for every entry of `profileNames` built standalone (catches NixOS-only options in personal profiles); `home-eval-aarch64` forces evaluation of the aarch64 sample's derivation path.
- VM test `home-installer-refuses-nixos`: runs `home-only.sh` on a NixOS node and expects the NixOS abort.
- CI job `home-installer` on `ubuntu-latest` without a preinstalled Nix: shellcheck `home-only.sh`, run it with `NIXOS_CENTRAL_FLAKE=git+file://$GITHUB_WORKSPACE --profile ci-user --install-nix --no-gpu-setup`, then assert the profile's settings are active (`EDITOR=nano` in a login shell), the auto-upgrade timer unit exists, and `~/.bashrc.backup` exists for a pre-seeded `~/.bashrc`; run `sudo bash home-only.sh` and expect the root refusal.
- `pages.yml`: copy `home-only.sh` to `site/home-only.sh`, add it to `paths`.

## Risks / Trade-offs

- [User timers run only while the user's systemd instance runs] → spec says "soon after the user is next logged in"; `Persistent = true` catches up. No lingering is enabled (would need root).
- [Host NVIDIA driver updated, recorded version no longer matches → GL apps fail] → summary and README document re-running `home-only.sh --replace-existing` (re-detects and rewrites facts) or editing the two values.
- [Personal profiles use NixOS-only options (`osConfig`, `nixos-central` options)] → `home-profile-*` checks build every selectable profile standalone in CI.
- [Copied shell helpers drift between scripts] → both shellchecked in CI; helpers are small and stable.
- [Running `nix run github:…` before flakes are enabled] → all `nix` calls in the script go through `nixx` with `--extra-experimental-features`.
- [`ci-` prefix as the test-profile marker is a convention] → documented next to `users/ci-user`.

## Migration Plan

Additive. Existing NixOS machines are unaffected; `mkHost` output must stay identical (existing `host-*` checks). k-nixos standalone users: move their profile into `users/<name>`, run `home-only.sh --replace-existing`; the old `~/.config/home-manager` is kept as a backup. Rollback: `home-manager generations` and run the previous generation's `activate`.

## Open Questions

- Whether a standalone `nixos-central-upgrade` / `nixos-central-try` equivalent is wanted later; manual update is documented as `nix flake update central --flake ~/.config/home-manager && home-manager switch --flake ~/.config/home-manager`.
