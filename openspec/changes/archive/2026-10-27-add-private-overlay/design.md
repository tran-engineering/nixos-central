# Design

## Context

- Machine flakes (`templates/host/flake.nix`) and home flakes (`templates/home/flake.nix`) are generated from templates with one input, `central`, and one `mkHost`/`mkHome` call.
- `mkHost` already takes `modules`. `mkHome` takes only facts. Both are stable interfaces and must stay backwards compatible.
- Upgrades update exactly one input: `central-update-flags.nix` (`--update-input central`) is shared by `system.autoUpgrade` and `nixos-central-upgrade`. Standalone homes run `nix flake update central` as `preSwitchCommands`. `nixos-central-upgrade` restores the whole lock file when it fails before installing a generation.
- `nixos-upgrade.service` runs as root. Flake inputs are fetched by the evaluating process, so for `git+ssh` inputs root's `ssh` must authenticate.
- The primary user's personal key `~/.ssh/id_ed25519` (no passphrase) is the agreed credential. On standalone homes the user's own `ssh` is used.

## Goals / Non-Goals

**Goals:**
- Installation and central stay public and anonymous. The overlay is added after first boot with one command.
- Unattended upgrades include overlay changes.
- An unreachable overlay never leads to a build without it.

**Non-Goals:**
- Secrets management (encryption, per-machine keys, deploy keys). Access control is the private repository's own.
- More than one overlay, or overlays for users other than the primary user.
- Desktop notifications for failed upgrades. The failure shows in `systemctl status nixos-upgrade` and `systemctl --failed`; a notification is a possible follow-up.

## Decisions

### `private` is an optional builder argument
`mkHost { …; private ? null; }` and `mkHome { …; private ? null; }`. When it is given:
- the primary user's home-manager config imports the overlay profile resolved for them (see "Overlay profiles");
- on NixOS, `private.nixosModules.default` is imported when the overlay exports it;
- the option `nixos-central.private.enable = true` is set (NixOS and home), so the upgrade modules can react.

Without it, the generated module lists are unchanged, and existing machine and home flakes build identical derivations.

*Alternative:* passing the overlay through `modules`. That already works for NixOS but not for `mkHome`, needs the user to know module wiring, and gives the upgrade no way to know there is an input to update.

### Overlay profiles
An overlay holds several people's setups, like `users/` in central: it exports `homeModules.<profile>`, plus optionally `homeModules.default` as fallback. The overlay can't choose by itself, because a module can't make `imports` depend on `config.home.username` (infinite recursion). So central resolves it with the same name it uses for its own profile:

```
 NixOS (mkHost):        name = user
 standalone (mkHome):   name = profile fact, else user
 overlay module =       homeModules.<name>  or  homeModules.default  or  throw (lists the profiles)
```

The failure is deliberate, for the same reason as an unreachable overlay: a configuration that declared an overlay never builds without it.

On standalone homes, `profile` names the person across both repositories. Central uses `users/<name>` or `_default`, the overlay `homeModules.<name>` or `default`. The "profile does not exist" warning only appears if neither has it. A profile that exists only in the overlay (like `kt` once it left central) is recorded with `nixos-central-private setup <url> --profile kt`, which rewrites the `profile = "...";` line of the home flake. `home-only.sh` still only offers central profiles, so the documented order is: install with `--profile _default`, then `setup … --profile kt`. On NixOS the profile is always the primary user's name, so `--profile` is refused there.

A private repository mirrors central's layout: `users/<name>/default.nix` becomes `homeModules.<name>`, and `users/_default` becomes `homeModules.default`.

### Overlays have no inputs
`mkHost`/`mkHome` throw if `private.inputs != {}`, with a message that overlays may only export modules. This keeps one nixpkgs (central's) and makes the lock file's `private` entry a single repository. Flake objects expose `inputs` (checked: `[]` for a module-only flake).

### Overlays select shared modules through `centralModules`
An overlay has no inputs, so it can't import `../../modules/home/dev-cli`. `mkHost` (via `home-manager.extraSpecialArgs`) and `mkHome` (via `extraSpecialArgs`) pass `centralModules`, an attrset of central's shared home modules by name: `general-tools`, `dev-cli`, `git`, `jj`, `fish`, `zsh`, `foot`, `ghostty`, `dev-desktop`, `idea`, `godot`, `drawio`. It is built from `modules/home/` with the internal modules (`standalone.nix`, `shell.nix`) excluded.

```
kt-private/flake.nix
  outputs = { ... }: {
    homeModules.default = { centralModules, pkgs, ... }: {
      imports = with centralModules; [ dev-cli git jj fish ghostty ];
      nixos-central.shell = "fish";
      programs.git.settings.user.email = "...";
    };
  };
```

It must be a *special* argument. Arguments set through `_module.args` can't be used in `imports` (infinite recursion). Profiles inside central can use it too, but relative imports keep working.

The names are a public interface from now on: renaming or removing one breaks overlays, so that is announced as breaking, like `mkHost` arguments. A check evaluates `centralModules` against the directory, so a new module can't be forgotten in the attrset.

*Alternative:* central exports `homeModules.<name>` as flake outputs. Overlays would still need central as an input to reach them, which is exactly what they can't have.

### Personal profiles move out of central
`users/kt` is deleted. Its content (module selection, shell, fonts, themes, alias) is the starting point of kt's overlay, together with what k-nixos had (identity, work files, personal apps, dotfiles).

Until the overlay is set up, `kt` resolves to `users/_default`, like any user without a profile. The overlay is applied on top of `_default`. Settings from `_default` the user doesn't want are overridden in the overlay (`lib.mkForce`), as personal profiles do today.

The shared modules lose their only importer, so `users/ci-modules` (test-only through the `ci-` prefix, not selectable) imports all of them via `centralModules` and selects fish. That also tests the `centralModules` path itself. The checks change accordingly: `host-eval-kt` becomes `host-eval-ci-modules`, `ci-home-kt-aarch64` becomes `ci-home-modules-aarch64`, and an x86_64 eval-only home check replaces `home-profile-kt`, which disappears because `ci-` profiles aren't selectable.

### Upgrades update `private` when declared
`central-update-flags.nix` becomes a function of `config`: `--update-input central`, plus `--update-input private` if `nixos-central.private.enable`. Standalone homes' `preSwitchCommands` become `nix flake update central` plus `private` when enabled. A failed fetch is an evaluation error, so every path fails before anything is installed:

```
 daily upgrade / nixos-central-upgrade
   update central + private --> evaluate --> fetch private (ssh as root)
                                               | fails
                                               v
                                   error; no generation; lock restored (upgrade cmd)
                                   or unchanged (auto-upgrade writes lock only on success? see risk)
```

Building without the overlay can't happen, because the overlay is referenced by the evaluated configuration and there is no conditional around it.

### Root authenticates as the primary user, for GitHub only
Central's NixOS base adds, unconditionally:
- `programs.ssh.knownHosts."github.com"` with GitHub's published Ed25519 host key (verified against `https://api.github.com/meta` in task 3.1);
- an ssh client block: `Match host github.com localuser root` → `IdentityFile /home/<user>/.ssh/id_ed25519`, `IdentitiesOnly yes`.

It's unconditional so that the first rebuild in `setup` (before the option is set) can fetch the overlay. A missing key file only makes ssh skip that identity. Other users and other hosts are unaffected. The key stays where the user put it, so rotating it in `~/.ssh` is picked up automatically.

### The `nixos-central-private` command
It's one script, in the system packages on NixOS and in `standalone.nix` for homes, and it detects which kind of machine it runs on.

```
 setup <url>
   1. mode: NixOS (/etc/nixos/flake.nix, re-exec with sudo) or home (~/.config/home-manager)
   2. standalone: add GitHub's host key to ~/.ssh/known_hosts if missing
   3. check access: nix flake metadata --refresh <url>   (as root on NixOS)
        fails --> print key path + "add it to GitHub", exit, nothing changed
   4. back up flake.nix + flake.lock
   5. edit flake.nix in the template's shape (with --profile, standalone only:
        `profile = "...";` -> `profile = "<name>";`):
        after `inputs.central.url = ...;`  add `inputs.private.url = "<url>";`
        `{ central, ... }:`                -> `{ central, private, ... }:`
        before `modules = [` (host) or `stateVersion` (home) add `inherit private;`
        any anchor missing --> restore, explain, exit
   6. activate: nixos-rebuild switch --flake /etc/nixos#<host>  |  home-manager switch --flake ...
        fails --> restore backups, exit non-zero
 remove: inverse edits, then activate; the lock entry is pruned by the build
```

`nix flake metadata` is the access check because it works for any flake URL (`git+ssh`, `github:`, `git+file` in tests) and exercises the same fetch path as the build.

## Risks / Trade-offs

- [`system.autoUpgrade` may write the updated lock file even when the build fails] → For a fetch failure, nothing can be written, because there is no new revision to lock. A build failure after a successful update behaves as today for `central`. Task 3.3 verifies the daily path leaves the lock unchanged when the overlay can't be fetched.
- [Root reading the user's key] → Root can read it anyway. The `Match` block limits use to GitHub fetches by root. A lost machine means rotating the personal key, which is an accepted trade-off.
- [`flake.nix` hand-edited away from the template shape] → `setup` refuses with a clear message instead of guessing.
- [The overlay drifts from central, e.g. it uses an option central later removes] → The upgrade fails visibly. Keep overlays to file placement and small settings.
- [GitHub rotates its host key] → The pinned key comes from central and updates with it. The failure until then is visible like any fetch failure.

## Migration Plan

Additive. Homes without `private` build identical derivations. Hosts without `private` differ only by the GitHub host key and the root-only SSH block, which every host gets (see above); `private`, `centralModules` and the update flags leave them unchanged (verified with the sample hosts' drvPaths before adding the SSH settings). The "customization" rule change is documentation-only for existing setups.
