# Proposal

## Why

Profiles can only choose between the shared default and writing everything themselves. The tools and settings in the `kt` profile of the old k-nixos flake (CLI tools, development and infra tooling, editors) are useful to more than one person, but there is nowhere in the central repository to put them so that a profile can opt in without copying them.

## What Changes

- Add shared home-manager modules in `modules/home/` that any profile can import. They work on NixOS machines and on standalone homes:
  - `general-tools`: everyday CLI utilities (archive, disk usage, media, network lookup, file inspection).
  - `dev-cli` (a directory, because it carries settings): development CLI tools, language toolchains, AI coding agents, infrastructure/cloud tools and Nix tooling. It also carries settings: cargo and pnpm on the PATH, and mise with a global Node.js as an overridable default.
  - `git` and `jj` (with jjui): each with workflow defaults that a profile can override.
  - `dev-desktop`: the Zed editor with its ACP agent bridge.
  - `idea`, `godot`, `drawio`: one module per graphical application.
  - `fish` (with the tide prompt), `zsh`: interactive shells with working defaults.
  - `foot`, `ghostty`: terminal emulators with readable defaults.
- Let a profile select the user's login shell (bash, fish or zsh; bash by default). NixOS machines apply it; the home installer only suggests the switch for the selected shell.
- Port the packages and settings from `k-nixos/users/kt` into these modules. Leave out packages already provided elsewhere (`htop`, `home-manager`, `nixos-rebuild`), duplicates, non-development GUI apps and personal identity (names, emails, fonts, shell prompt).
- Add a `users/kt` profile that imports the default profile and all shared modules. Personal settings follow in a later change.
- CI evaluates profiles instead of building them: package builds are trusted to nixpkgs' Hydra. The `kt` profile is evaluated as a standalone home on x86_64 and aarch64, and as a NixOS user.
- Document in the README how a profile opts into the shared modules.

## Capabilities

### New Capabilities
- `home-modules`: shared, opt-in home-manager modules in the central repository that profiles include. Covers where they live, that they are never offered as profiles, that they work on NixOS and standalone, that their defaults can be overridden, and which modules exist.

### Modified Capabilities
- `user-profiles`: a profile can select the login shell, applied on NixOS machines.
- `home-installer`: the shell-switch hint follows the profile's selected shell instead of every shell the profile happens to provide.

## Impact

- New files: `modules/home/general-tools.nix`, `modules/home/dev-cli/` (several files), `modules/home/dev-desktop.nix`, `modules/home/{git,jj,idea,godot,drawio,zsh,foot,ghostty}.nix`, `modules/home/fish/`, `modules/home/shell.nix` (shell option, part of every profile), `users/kt/default.nix`.
- Changed: `modules/user.nix` (login shell from the profile, `shell.nix` for every NixOS user), `lib.mkHome` (`shell.nix` for every standalone home), `home-only.sh` (`shell_hint`).
- `flake.nix`: the `home-profile-<name>` checks switch from building to evaluating each selectable profile. New eval-only checks cover `kt` on aarch64 and as a NixOS user. `_default` is still built by the existing `ci-home-default` sample home.
- The home installer (`home-only.sh`) now offers `kt` as a profile. No code change is needed for that.
- CI does not download the `kt` closure (IntelliJ IDEA, Godot, the cloud CLIs), so build time and disk use stay as they are.
- `README.md`: new subsection under "Users and profiles", and the sample homes list in "Development".
