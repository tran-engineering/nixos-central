# Design

## Context

See proposal.md for motivation, and the `central-command` spec for the behavior of the new command.

Today two module systems contribute the user commands:

```
                         NixOS machine                         standalone home
 NixOS modules           upgrade, try, diff, private            -
   (environment.systemPackages)
 home-manager modules    update-notice                          upgrade, diff, private,
   (home.packages)       (sharedModules in modules/user.nix)    update-notice
                                                                (lib.mkHome, standalone.nix)
```

On NixOS, home-manager runs with `useUserPackages = true`, so `home.packages` lands in `/etc/profiles/per-user/<user>`. That directory comes before `/run/current-system/sw` in PATH. If both module systems installed a `nixos-central`, the home-manager one would hide the system one.

The scripts re-run themselves as root with `exec sudo "$0" "$@"` (`upgrade`, `try`, `private`). The shell hook calls the notice script by store path (`modules/home/update-notice.nix`, `call`), not through PATH.

## Goals / Non-Goals

**Goals:**
- Each subcommand stays a separate script with the logic it has today. The change is in how they are found, named and described, not in what they do.
- Adding a subcommand means touching one module.
- Help, chooser and completion are generated from one list, so they can't drift apart.

**Non-Goals:**
- Rewriting the scripts in another language or merging them into one file.
- Dynamic completion (branches, URLs, profiles).
- Prompting for arguments in the chooser.
- Renaming the systemd-only scripts `nixos-central-gc` and `nixos-central-reboot-notify`.

## Decisions

### 1. A registry option in both module systems, one dispatcher per PATH

Both module systems get an option `nixos-central.commands`, an attrset of subcommands keyed by name:

```nix
nixos-central.commands.upgrade = {
  package = upgrade;             # its main program is exec'd
  description = "Install the latest update and use it now";
  usage = "[--private]";         # shown in help after the name
  order = 10;                    # position in help and menu
  chooser = true;                # offered by the interactive menu
  completions = { "" = [ "--private" ]; };  # see Decision 4
};
```

The option type (`option.nix`) and the dispatcher builder (`default.nix`) live in `nixos-central-internal/command/` and are shared by both module systems. The data of each subcommand except `package` is in `nixos-central-internal/command/subcommands.nix`. Upgrade and diff each have a NixOS and a standalone build, so this keeps their help text in one place. Modules write `subcommands.upgrade // { package = ...; }`.

- **NixOS** (`modules/base/command.nix`) builds `nixos-central` from its own commands merged with `config.home-manager.users.<primary user>.nixos-central.commands`, and puts it in `environment.systemPackages`.
- **home-manager** (`modules/home/command.nix`) declares the option and installs a dispatcher in `home.packages` **only when `nixos-central.updateNotice.standalone` is true**, which means only on standalone homes.

```
 modules/base/{upgrade,try,diff,private}.nix --+
                                               +--> NixOS: nixos-central  (systemPackages)
 modules/home/update-notice.nix  -- status ----+
            (via home-manager.users.<u>)       |
                                               +--> standalone home: nixos-central (home.packages)
 modules/home/standalone.nix  -- upgrade, diff, private
```

The subcommand scripts are no longer installed on PATH. The dispatcher refers to them by store path. This satisfies "old names are gone" without renaming store derivations.

*Alternatives:*
- **Git-style lookup of `nixos-central-<sub>` on PATH.** Rejected: it keeps the old names on PATH, which the spec forbids, and it can't produce descriptions for help or the chooser.
- **A single static script with a `case` over all subcommands.** Rejected: NixOS-only and home-only subcommands, and builds of the same subcommand that differ per machine (upgrade with or without an overlay), would turn into conditionals inside one large file.

### 2. Dispatcher: bash, `exec` by store path

`nixos-central` is a `writeShellApplication`:

```
 args?
  +-- help | -h | --help          -> help on stdout, exit 0
  +-- <known sub> [args...]       -> exec <store path of sub> "$@"
  +-- <unknown>                   -> error + help on stderr, exit 2
  +-- (none)
        +-- [ -t 0 ] && [ -t 1 ]  -> gum choose (chooser = true entries)
        |                            cancelled -> exit 1 (or gum's status)
        |                            chosen    -> exec <sub> (no args)
        +-- otherwise             -> help on stderr, exit 2
```

Because the subcommand runs by `exec` with its store path as `$0`, `exec sudo "$0" "$@"` inside the subcommands keeps working.

Usage texts inside the scripts change to the new form (`usage: nixos-central upgrade [--private]`).

### 3. Chooser with gum, data from the registry

The menu lists one line per entry with `chooser = true`, made of the name padded to a column and the description. gum's selected line is cut back to the name. This avoids relying on newer gum label options. gum comes from the pinned nixpkgs (0.17.0) in the dispatcher's `runtimeInputs`, so it is in the closure on every machine and home, but only the chooser runs it.

*Alternatives:* bash `select` (no dependency, but looks rough) and fzf (good for fuzzy search, but not what was asked for). Both were rejected in exploration.

### 4. Completion generated from `completions`

Each entry maps "previous word" to candidates: `""` is the first argument after the subcommand, and `setup` is the word after `setup`. That is enough for every fixed option today:

| sub     | completions                                 |
|---------|---------------------------------------------|
| upgrade | `"" = [--private]`                          |
| private | `"" = [setup remove]; setup = [--profile]`  |
| status  | none (`--if-stale` is hidden)               |
| diff    | none                                        |
| try     | none                                        |

The dispatcher package writes `share/bash-completion/completions/nixos-central`, `share/zsh/site-functions/_nixos-central` and `share/fish/vendor_completions.d/nixos-central.fish` from this data at build time.

- On NixOS these are found through the existing `programs.<shell>.enable` and bash completion settings, which link `share/` from system packages.
- On standalone homes they are found in the home-manager profile. home-manager's fish and zsh modules add the profile's completion directories, and for bash, bash-completion looks in `XDG_DATA_DIRS`. See Risks.

### 5. `status` replaces `update-notice`; the shell hook stays direct

`modules/home/update-notice.nix` registers `status` with its package. The shell hook keeps calling the script by store path with `--if-stale`, so new shells don't depend on the dispatcher and don't pay for an extra `exec`. The script's usage line names `nixos-central status`. `--if-stale` is still accepted but isn't advertised.

### 6. Default overlay URL: one constant, passed into the private package

`nixos-central-internal/lib/default-private.nix` holds `"git+ssh://git@github.com/tran-engineering/nixos-central-private"`. `nixos-central-internal/private/default.nix` takes it as an argument and prepends it to the script, as it does today with `GITHUB_HOST_KEY`. A fork edits this one file.

*Alternative:* an option `nixos-central.private.defaultUrl` in both module systems. Rejected: it duplicates the option, and per-machine overrides weren't asked for. The constant can later become an option's default without changing behavior.

### 7. `private` without an action works without root

`main` in `nixos-central-private.sh` handles the no-argument case before `detect` re-runs itself through sudo. Detection is split into "find the flake" (no root needed, because `/etc/nixos/flake.nix` is world-readable) and "become root" (only for `setup` and `remove`). The overlay URL is read from the `inputs.private.url = "...";` line that `setup` writes. `setup` without a URL announces the default and continues as if it had been given. When `--profile` follows directly after `setup`, it is not taken for the URL.

## Risks / Trade-offs

- **[Two dispatchers on NixOS if the standalone check is wrong]** The home-manager module might install a dispatcher on a NixOS machine and hide the system one. → It keys on `updateNotice.standalone`, which only `standalone.nix` sets, and a VM test asserts that `command -v -a nixos-central` returns one path.
- **[Completions not picked up on standalone homes]** For example, bash on a distro without bash-completion, or zsh/fish without the home-manager shell modules. → No extra wiring was needed. The completion files are in the home profile (`~/.nix-profile/share`). bash-completion finds them through `XDG_DATA_DIRS` and next to the command, fish finds them through `XDG_DATA_DIRS`, and home-manager's zsh module adds every `$NIX_PROFILES` entry to `fpath`. Nix's profile script sets both variables on other distributions. The `home-command` VM test activates a real standalone home and checks bash and fish completion and the zsh `fpath` lookup. A distro without bash-completion has no bash completion at all, which is accepted: a missing completion only loses convenience, never behavior.
- **[gum closure on every machine]** About 13.5 MiB, even where nobody uses the chooser. → Accepted.
- **[gum behavior across versions]** Exit codes on cancel, and output when stdout is a terminal. → The dispatcher treats any non-zero gum exit as cancel and changes nothing. gum's version is pinned by the flake lock.
- **[Breaking rename]** Old names stop working at the next update, and there are no aliases, by decision. → The README and the hints all change in the same update. The reboot notification and the stale notice are the places most people meet the names, and both name the new command.
- **[Registry merging across module systems]** NixOS reads the home-manager user's evaluated config. That is already done for `shell` in `modules/user.nix`, so there is no new coupling pattern, but an evaluation error in home-manager also surfaces when the dispatcher is built. → Accepted.

## Migration Plan

1. Land everything in one change, so no update ships both naming schemes or a half-renamed set of hints.
2. Machines and homes pick it up with the daily upgrade. Users see the new name in the next reboot notification or stale notice, and in the README.
3. Rollback: boot or activate the previous generation, which brings back the old commands. No state or file format changes. The private overlay lines in local flakes stay the same.
