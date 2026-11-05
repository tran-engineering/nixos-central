# Proposal

## Why

The user-facing tools are five separate commands (`nixos-central-upgrade`, `-try`, `-diff`, `-private`, `-update-notice`). To find them you have to know them or read the README. A single `nixos-central` command with subcommands, shell completion and an interactive chooser makes them easy to discover, especially for users who don't read the README.

## What Changes

- New command `nixos-central` with the subcommands `upgrade`, `diff`, `status`, `private` and `try` (NixOS only), plus `help`.
- Running `nixos-central` without arguments on a terminal opens a menu (gum) to pick a subcommand. The chosen subcommand runs without arguments. `try` is not in the menu, because it needs a branch. Without a terminal, plain `nixos-central` prints help and exits with an error.
- Shell completion for bash, zsh and fish covers subcommands and their fixed options. Branch names for `try` are not completed.
- **BREAKING**: `nixos-central-upgrade`, `nixos-central-try`, `nixos-central-diff`, `nixos-central-private` and `nixos-central-update-notice` are removed, with no aliases. Their behavior moves to the subcommands unchanged, except:
  - `nixos-central-update-notice` becomes `nixos-central status`. `--if-stale` stays for the shell hook but is not listed in help.
  - `nixos-central private setup` without a URL uses the default overlay `git+ssh://git@github.com/tran-engineering/nixos-central-private`. A fork can change this default.
  - `nixos-central private` without an action shows whether an overlay is declared (and which) and the usage, and changes nothing.
- All messages that name a command (the reboot notification, the update notice hint, usage and error texts, the home installer's NixOS refusal, the README) use the new names.
- The internal, systemd-only scripts `nixos-central-gc` and `nixos-central-reboot-notify` keep their names. They are not user commands.

## Capabilities

### New Capabilities
- `central-command`: the single `nixos-central` command, which covers subcommand dispatch, help, the interactive chooser, shell completion, and which subcommands exist on NixOS machines and on standalone homes.

### Modified Capabilities
- `system-updates`: `try`, `upgrade`, `upgrade --private` and `diff` are subcommands. The reboot notification names `nixos-central diff`.
- `home-configuration`: on standalone homes, `upgrade`, `upgrade --private` and `diff` are subcommands.
- `private-overlay`: `private setup` and `private remove` are subcommands. The setup URL is optional and falls back to a default overlay. Plain `private` shows the overlay state.
- `stale-update-notice`: the on-demand command is `nixos-central status`, and the hint names `nixos-central upgrade`.
- `home-installer`: the NixOS refusal points to `nixos-central upgrade`.

## Impact

- Code: `modules/base/{upgrade,try,diff,private,reboot-notify}.nix`, `modules/home/{update-notice,standalone}.nix`, `modules/options.nix`, `nixos-central-internal/{home-upgrade,diff,private}`, `nixos-central-internal/installer/home-only.sh`, and a new dispatcher package under `nixos-central-internal/`.
- New runtime dependency: `gum`, prebuilt from nixpkgs (about 4.4 MiB download, 13.5 MiB unpacked), on every NixOS machine and standalone home.
- Tests: the VM tests in `nixos-central-internal/tests/default.nix` that call the old commands or check their usage texts.
- Docs: README sections on updates, trying branches and the private overlay.
- Users: anyone with the old names in muscle memory, notes or scripts has to switch to the new names.
