# Design

## Context

- Profiles are home-manager modules under `users/<name>/`. `nixos-central-internal/lib/profiles.nix` treats **every directory** in `users/` as a profile: it resolves login names against it and offers all non-`ci-` directories to the home installer.
- The same profile module is used on NixOS (`modules/user.nix`, home-manager with `useGlobalPkgs`) and in standalone homes (`lib.mkHome`). In both cases the package set comes from `nixos-central-internal/lib/nixpkgs.nix` (unfree allowed, `pkgs.unstable` overlay), so a module sees identical packages in both.
- Standalone homes get GPU access through `targets.genericLinux` plus a one-time `non-nixos-gpu-setup`, not nixGL. The `config.nixGLWrap` calls in k-nixos have no counterpart here.
- `modules/home/standalone.nix` already provides the `home-manager` CLI on standalone homes, and NixOS hosts already have `nixos-rebuild`. `htop` is in `users/_default`.
- CI (`nix flake check`) builds every `nixosConfigurations.ci-*` host, every selectable profile as a standalone home (`home-profile-<name>`), and evaluates (without building) every sample home whose platform differs from the runner's.
- Package availability was checked against the pinned inputs: every ported package exists and is not broken on `x86_64-linux` and `aarch64-linux`. The unstable `zed-editor` ships `share/applications/dev.zed.Zed.desktop`.

## Goals / Non-Goals

**Goals:**
- One import line per module in a profile; no options to set.
- Modules usable with or without `../_default`.
- Every module evaluated by CI on NixOS, standalone x86_64, and standalone aarch64, without building or downloading its packages.

**Non-Goals:**
- Enable flags or other options on the modules (`nixos-central.dev-cli.enable`). Importing a module is the switch.
- Porting kt's personal configuration (identity, fish/tide, plasma-manager, config files, ai-agent symlinks, non-development GUI apps). That is a later change to `users/kt`.
- Making the module set selectable from the machine flake or the home installer.

## Decisions

### Location: `modules/home/`, imported by relative path
Modules live next to `standalone.nix` in `modules/home/`. A profile imports them with `../../modules/home/<name>.nix` (or the directory for `dev-cli`).

*Alternatives:* `users/_modules/` would be found by `profiles.nix` as a profile directory and offered by the installer. Filtering it there would add a special case to profile resolution for no benefit. Passing the modules through `specialArgs`/`extraSpecialArgs` (e.g. `centralModules.dev-cli`) would need wiring in both `modules/user.nix` and `mkHome`, and a relative import is already how profiles reuse `_default`.

### Layout: bundles plus single-tool modules
```
modules/home/
  general-tools.nix      packages only
  dev-cli/
    default.nix          packages (grouped by comment) + imports
    environment.nix      cargo/pnpm PATH, mise
  git.nix                git, LFS, workflow defaults
  jj.nix                 jj, jjui, workflow defaults
  dev-desktop.nix        Zed + Claude agent bridge
  idea.nix               IntelliJ IDEA
  godot.nix              Godot
  drawio.nix             draw.io
```
Tools that someone may well want without the rest of a bundle (git and jj with their opinionated defaults; large single applications like IDEA and Godot) are their own modules. Bundles do not import them, so a profile lists every module it wants. `dev-cli` stays a directory because of its settings file. A module whose settings grow past ~30 lines becomes a directory the same way.

### Overridable defaults: `lib.mkDefault` on each leaf, never on an attrset
Behavior settings (git `pull.rebase`, `push.autoSetupRemote`, `rebase.autoStash`, `lfs.enable`; jj `remotes.origin.auto-track-*`, `git.private-commits`, `snapshot.max-new-file-size`; mise's global Node.js) are written as `lib.mkDefault` per value.

`programs.jujutsu.settings` and `programs.git.settings` are freeform attrsets. A single `settings = lib.mkDefault { ... }` would lose **as a whole** as soon as the profile sets any key at normal priority, such as `user.name`. Every default would then disappear silently. Per-leaf `mkDefault` merges with the profile's keys and only yields where the profile sets the same key.

Installing tools (`home.packages`, `programs.<tool>.enable = true`) is not a behavior default and is set normally. Setting `enable = true` agrees with `_default` when both are imported.

### Zed through `programs.zed-editor`, no custom desktop entry
`programs.zed-editor.enable = true` with `package = pkgs.unstable.zed-editor` replaces kt's separate package plus `package = null`. The custom `xdg.desktopEntries."dev.zed.Zed"` existed only because nixGL wrapping hid the package's own entry. The package ships `dev.zed.Zed.desktop`, so it is dropped. The `zed` → `zeditor` shell alias stays (`home.shellAliases`, which works for bash and fish). Font settings are personal and stay out.

### pnpm via session variables, not fish config
kt set `PNPM_HOME` and its PATH entry in `fish.nix`. In `dev-cli` they become `home.sessionVariables`/`home.sessionPath`, which apply to every shell home-manager manages. `pnpm` itself is not installed by the module; it comes through Node.js/corepack via mise, as in k-nixos.

### Login shell: an option in the profile, read by NixOS
`modules/home/shell.nix` declares `nixos-central.shell` (enum `bash`/`fish`/`zsh`, default `bash`) in the home-manager configuration. It is added to every profile: through `home-manager.sharedModules` in `modules/user.nix`, and as a module of `lib.mkHome`. It also enables the selected shell's `programs.<shell>.enable`, so a selection works even without the matching shared module.

On NixOS, `modules/user.nix` reads `config.home-manager.users.<user>.nixos-central.shell`. For fish or zsh it sets `users.users.<user>.shell` and the system-level `programs.<shell>.enable`, which NixOS requires for a login shell (`/etc/shells`, vendor completions). For bash nothing is set, so existing hosts keep identical derivations.

Standalone homes cannot change the login shell without root. `home-only.sh`'s `shell_hint` evaluates the option from the local flake (like the GPU setup package) and suggests `chsh` only for the selected shell, not for every shell found in the profile.

*Alternatives:* making the shell module itself select the login shell breaks when a profile imports both fish and zsh, and mixes "have a tool" with "use it as login shell". A `shell` argument to `mkHost`/`mkHome` would put user customization in the local flake, which `user-profiles` forbids, and would change the stable interface.

### Shells and terminals
- `fish/` is a directory: `default.nix` plus `tide.fish`, kt's tide variables (ported verbatim). They are installed to `fish/conf.d/tide.fish` with `lib.mkDefault` on the source, so a profile replaces the prompt by setting that file. Tide added as a home-manager plugin never runs its install hook, so without these variables the prompt would be broken. Plugins: tide, fzf-fish (with `fzf` and `fd`, which it calls), z, fish-cd-gitroot (pinned by hash, as in k-nixos). The `ls = eza` alias is personal and stays out.
- `zsh.nix` has no k-nixos source. It uses home-manager's built-ins only: completion, autosuggestion, syntax highlighting, and history (`share`, `ignoreAllDups`, larger size), with no framework or prompt theme.
- `foot.nix` and `ghostty.nix` carry kt's non-personal settings as per-leaf `mkDefault` (window size; padding, cursor, scrollback, copy-on-select, notifications, split dimming, keybindings for ghostty). Font family, the foot kitty theme, `term = kitty` and ghostty's `dankcolors` theme are personal and go to `users/kt`, together with the FantasqueSansM Nerd Font they name.
- Icon font: `fish` and `foot` install `nerd-fonts.symbols-only` and set `fonts.fontconfig.enable`. fontconfig falls back to it for the glyphs whatever the main font is. Ghostty ships Nerd Font symbols built in. Standalone homes already enable fontconfig. On NixOS it makes the per-user font directory visible.

### Packages dropped or moved
- Not ported: `htop` (in `_default`), `home-manager` (in `standalone.nix`; conflicts with `programs.home-manager`), `nixos-rebuild` (NixOS hosts have it; meaningless standalone), duplicate `jq` and `unstable.herdr`.
- `mesa-demos` and `vulkan-tools` are not ported. GPU checks are done ad hoc (`nix shell nixpkgs#vulkan-tools`).
- `nmap`, `sops`, `age` go to `dev-cli`.

### CI: evaluate profiles, trust Hydra for packages
The packages in the modules are built by nixpkgs' Hydra and served from cache.nixos.org. CI only has to show that the configuration is valid: options exist, types match, and every package attribute resolves for the platform. Forcing `drvPath` of the activation package (or system toplevel) checks that without building or downloading anything.

- **Standalone x86_64**: the generic `home-profile-<name>` checks in `flake.nix` switch from `activationPackage` to an eval-only check (`writeText` of the `drvPath`, the same pattern as `home-eval-*`). Otherwise `kt`, as a selectable profile, would be built automatically. Every selectable profile is affected. `_default` keeps a real build through the `ci-home-default` sample home, which stays as it is.
- **Standalone aarch64**: add `homeConfigurations.ci-home-kt-aarch64 = ciHome { system = "aarch64-linux"; profile = "kt"; }`. The existing `home-eval-*` rule picks it up.
- **NixOS**: an eval-only check `host-eval-kt` for `ciHost "ci-kt" { desktop = "none"; user = "kt"; }`, built from `centralLib.mkHost` in `checks` rather than added to `nixosConfigurations`, because every `nixosConfigurations` entry is built by the `host-*` rule. This checks that the modules evaluate on NixOS, where `targets.genericLinux` is absent.

*Alternative:* keep `home-profile-*` as builds and exclude `kt`. That is a special case by name that every future heavy profile would need again.

## Risks / Trade-offs

- [Evaluation does not catch build-time failures: a package that fails on Hydra (channels advance even when individual packages fail), or file collisions in the combined `home-path` environment] → These surface on the machine's next update as a failed build. The previous generation stays active (NixOS: staged boot entry not replaced; standalone: switch fails, current home kept). Collisions are checked once during implementation with a local build (task 4.3).
- [`unstable` packages (`claude-code`, `opencode`, `herdr`, `talosctl`, `zed-editor`, `claude-agent-acp`, `godot`) move faster and break more often, and evaluation won't notice] → A broken one can be pinned back to stable or temporarily removed from the module.
- [Users of the `git` and `jj` modules get kt's workflow opinions] → All are `mkDefault` and listed in the README. A profile overrides them by setting the same option.
- [Unfree packages (`terraform`, `claude-code`, `jetbrains.idea`) bind every including user to their licenses] → The repository already allows unfree globally. Including a module is the opt-in.
- [rustup's toolchains and mise's Node.js are downloaded at runtime, outside Nix] → Same as in k-nixos. These are user-managed by design.

## Migration Plan

Additive. No existing profile imports the modules, so `_default` users and `ci-user` are unaffected. Machines with user `kt` switch from `_default` to `users/kt` on their next update. `users/kt` keeps `_default`'s contents via import, so nothing they have today disappears. Rollback: revert the commit, or boot the previous generation.
