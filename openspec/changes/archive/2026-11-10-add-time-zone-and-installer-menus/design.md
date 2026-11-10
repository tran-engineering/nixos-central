# Design

## Context

- Machine facts flow `install.sh` → `templates/host/flake.nix` (sed placeholders) → `mkHost`/`hostModules` (`nixos-central-internal/lib/default.nix`) → `options.nixos-central.*` (`modules/options.nix`) → a base module. `keyboardLayout` is the closest existing fact and is the model for `timeZone`.
- Nothing in the repo sets `time.timeZone` today, so NixOS falls back to UTC. A working-tree edit (uncommitted) adds `time.timeZone = lib.mkDefault "Europe/Zurich"` to `modules/base/default.nix`; this change replaces it.
- `install.sh` reads every answer through `ask`/`ask_secret` with `read … </dev/tty`, because the script itself arrives on stdin (`curl | sh`). It re-executes itself under sudo via `declare -f`, and `init_globals` runs again afterwards. Anything resolved before `ensure_root` is lost.
- The installer runs in two ways: `nix run $CENTRAL#installer` from the image's `start.sh`, a plain `writeShellScriptBin` without runtime inputs, and `curl … | sh` on any NixOS live image.
- The e2e test (`tests/e2e/run.py`) drives the installer and `start.sh` with pexpect over a serial console after `export TERM=dumb`. It matches exact prompt texts such as `Desktop \[kde\]: `.
- gum 0.17 is in the pinned nixpkgs. `gum choose` and `gum filter` take options as arguments, so stdin can be `/dev/tty`. `choose --selected` preselects a default, and `confirm --default` sets the yes/no default. At start it queries the terminal (OSC 11, then cursor position) and waits for the cursor-position reply. The Linux console sends that reply; a test harness has to send it itself.

## Goals / Non-Goals

**Goals:**
- One prompt layer in `install.sh` that hides the gum vs. plain decision, so the call sites stay simple.
- Plain prompts stay byte-identical to today's, so the existing e2e expectations still hold.

**Non-Goals:**
- Making gum mandatory, or using it for free text and secrets.
- Testing the gum UI in the serial-console e2e test.

## Decisions

### 1. `timeZone` is a machine fact with default `Europe/Zurich`

`mkHost`/`hostModules` gain `timeZone ? "Europe/Zurich"`. `options.nixos-central.timeZone` is a `str` matching an IANA-style name (`[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*`, which also allows `UTC`), with default `"Europe/Zurich"`. The base sets `time.timeZone = lib.mkDefault config.nixos-central.timeZone;`.

- *Why a fact, not only a base default:* the installer must record the answer somewhere, and facts in the machine flake are the established place for it (README "How a machine is configured").
- *Why `mkDefault`:* a machine's `modules` (or a later automatic time zone feature) can set `time.timeZone` without a conflict, as the spec requires.
- *Why not validate against tzdata in Nix:* `pathExists "${pkgs.tzdata}/…"` forces realising tzdata during evaluation (import from derivation), which breaks the eval-only cross-system checks. The installer validates instead, and a typo made by hand later still fails visibly: systemd logs an unknown zone and falls back to UTC.
- *Alternative:* default `UTC` for flakes without the fact (no change to existing machines). Rejected because the existing machines are expected to be on Zurich time; see proposal.

The template gets `timeZone = "@TIME_ZONE@"; # e.g. Europe/Zurich; list: timedatectl list-timezones`, placed next to `keyboardLayout`.

### 2. Time zone validation uses the live system's zone list

Valid names come from `timedatectl list-timezones`, read once in `preflight`. If that command fails, the list comes from the zone files under `/etc/zoneinfo`. The live image's tzdata comes from a NixOS release close to the one being installed; zones added or removed in between are negligible. `UTC` is always in the list.

### 3. One prompt layer: `choose`, `choose_filtered`, `confirm`, plus the existing `ask`

New helpers in `install.sh`:

- `choose VAR "Question" default options...`: `gum choose --header … --selected default` when menus are available. Otherwise it prints `Available …: …` and loops on `ask VAR "Question" default` until the answer is one of the options, printing `Choose one of: …` after a wrong answer. This is exactly what the call sites do today, so the plain output does not change.
- `choose_filtered VAR "Question" default hint options...`: `gum filter` with the default listed first, so Enter takes it before anything is typed and typing searches from an empty box. (Pre-filling the search with `--value default` was rejected: the user would have to delete it first.) An Enter without matches returns nothing, and the list is shown again. Without menus it behaves like the plain path of `choose`, but without listing 400 names. Its hint is `Unknown time zone. See the valid names with: timedatectl list-timezones`.
- `confirm "Question" yes|no`: `gum confirm --default=…` with stdout to `/dev/null` (it prints nothing there, and gum then skips its terminal queries) when menus are available. Otherwise it uses `ask` with `[Y/n]` or `[y/N]` and today's accepted answers.
- Retry or skip for the overlay uses `choose` with `Retry` and `Skip`. The plain form keeps `Retry, or skip the overlay? (r/s) [r]` and the `r`/`s` answers.

After a choice from a list, the helpers print `Question: answer`, because the menu disappears and the answer would otherwise not be on screen (typed answers stay visible anyway).

Every gum call runs with `</dev/tty 2>/dev/tty` (its screen goes to the terminal even after stderr is redirected into the install log) and its answer captured from stdout. gum 0.17 exits with 130 on Ctrl-C everywhere. Escape exits with 1 from `choose` and from `filter` (the first Escape only leaves the search box), and that is treated as cancel. From `confirm`, Escape also exits with 1, which is the same status as "No", so it counts as no. On cancel the installer calls `die "Aborted. Nothing was changed."`. This happens only before the disk is touched, because menus appear only before `install_system`. The one exception is the final "Reboot now?", where a cancel is treated as "no".

- *Alternative:* whiptail or dialog. They are uglier, and dialog needs ncurses terminfo on the console. gum was requested.

### 4. When menus are used

`MENUS=1` only if all of these hold, decided once in `preflight` (after `ensure_root`, so the decision survives the sudo re-exec):

- `/dev/tty` is readable and writable
- `TERM` is set and not `dumb`
- `NIXOS_CENTRAL_PLAIN` is unset (an escape hatch for scripting and debugging, documented in `--help`)
- a gum binary is found

gum is found as `gum` on `PATH` (the image ships it), or otherwise built from the central repository's nixpkgs:

```
nix build --no-link --print-out-paths --inputs-from "$CENTRAL" nixpkgs#gum
```

This is the same source as `run_tool`, but run once and with the store path remembered, so later questions don't each start `nix shell`. If the build fails, the installer prints one info line and uses plain prompts.

The keyboard layout question comes before `apply_keyboard_layout` and uses a menu too. Arrow keys don't depend on the layout, so this works.

### 5. Installation image

`iso/default.nix` adds `pkgs.gum` to `environment.systemPackages` and to `start`'s `runtimeInputs`. `start.sh`'s `ask` gets the same rule: `gum confirm` when `TERM` is not `dumb` and gum is present, otherwise today's `[Y/n]` prompt. The e2e test boots this image over serial with `TERM=dumb`, so its expectations hold.

### 6. Tests

- VM check in `tests/default.nix`: a host with `timeZone = "America/New_York"` reports that zone through `timedatectl show -p Timezone --value`. A host without the fact reports `Europe/Zurich`. A host whose `modules` set `time.timeZone` evaluates without a conflict.
- e2e (plain path):
  - the prompt flow gains `Time zone \[Europe/Zurich\]: `, answered first with an invalid value and then with a valid one
  - the flag run passes `--time-zone`
  - the installed flake contains the recorded `timeZone`
  - the summary contains the `time zone` line
  - `--time-zone Bogus/Zone` aborts before the disk is touched
- The gum path is checked by hand on the image's tty1 (task list). An automated check would need a pexpect run with `TERM=linux` that sends arrow keys; that is possible later but not required here.

## Risks / Trade-offs

- [gum's TUI on the bare Linux console (16 colors, no Unicode font for some glyphs)] → Use ASCII-safe prefixes (`--cursor "> "`, `--selected-prefix "* "`, `--unselected-prefix "  "`), and check on tty1 by hand.
- [Menu and plain paths drift apart] → Both paths are implemented inside the same helper, and call sites never branch on `MENUS`.
- [Existing machines switch from UTC to Zurich on the next automatic update without a prompt] → This is intended. It is documented in the README and in the commit message, and changing it back is one fact.
- [An extra download on non-image live systems, about 10 MB] → It happens once, can fail without consequence, and has a plain fallback.
- [The live system's time zone list differs from the installed tzdata] → Only for zones added or renamed between releases. A missing zone falls back to UTC visibly; accept.

## Migration Plan

There are no manual steps. Existing machine flakes keep building, and they pick up `Europe/Zurich` on the next update. Rollback: earlier generations in the boot menu, or `timeZone = "UTC";` in the machine flake.
