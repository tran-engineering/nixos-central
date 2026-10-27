# Design

## Context

- System state on a NixOS machine is three links: `/run/booted-system`,
  `/run/current-system` and the newest generation `/nix/var/nix/profiles/system`
  (`system-<N>-link`). The daily upgrade (`nixos-rebuild boot`) moves only the
  profile; `nixos-central-upgrade` moves profile and current system;
  `nixos-central-try` moves only the current system.
  `modules/base/reboot-notify.nix` already defines "staged" as profile ≠ booted
  and profile ≠ current.
- Standalone homes always `home-manager switch`, so the newest generation
  (`~/.local/state/nix/profiles/home-manager`, `home-manager-<N>-link`) is the
  active one.
- Scripts are `writeShellApplication`s: NixOS ones in `modules/base/*.nix`,
  home ones packaged with `callPackage` from `nixos-central-internal/<name>/` and
  added in `modules/home/standalone.nix` (`home-upgrade`, `private`).
- `nixos-central-gc` keeps old generations for 30 days, so in the usual case a
  previous generation exists, but it may not be N-1.
- `dix` 1.4.2 is in the pinned nixpkgs. It takes two store paths, runs as an
  unprivileged user, and exits 0 with only a size line when nothing changed.

## Goals / Non-Goals

**Goals:**
- One command name with no arguments on both kinds of machine. It never writes
  anything.

**Non-Goals:**
- Choosing arbitrary generations (`nixos-central-diff 38 41`). Run `dix` on the
  `system-<N>-link` paths for that. Can be added later without breaking the
  no-argument form.
- Diffing the home part of a NixOS machine separately. Home-manager there is a
  NixOS module, so it is part of the system closure and appears in the system diff.

## Decisions

### `dix`, the tool `nh` uses
The user wants the output they know from `nh`. *Alternatives:* `nvd` (older
nh, similar output, already in `dev-cli`); `nix store diff-closures` (no extra
dependency, but noisier and less readable). `dix` is small and only pulled in
as `runtimeInputs` of the command.

### One script package, two modes
`nixos-central-internal/diff/default.nix` (`callPackage`, arguments `dix`,
`coreutils` and `mode = "system" | "home"`) builds `nixos-central-diff`.
`modules/base/diff.nix` adds it with `mode = "system"` to
`environment.systemPackages`; `standalone.nix` adds it with `mode = "home"` to
`home.packages`. Generation listing, the "no earlier generation" message and
usage are shared. Unlike `upgrade`, which has two separate files, the shared
logic here is most of the script. It is not in `modules/home/`, so it doesn't
become a `centralModules` name.

### Choosing what to compare
```
system mode:
  staged  = readlink -f /nix/var/nix/profiles/system
  current = readlink -f /run/current-system
  staged != current  -> dix current staged   "Pending on next reboot (generation <N>):"
  else               -> previous/newest below

previous/newest (both modes):
  N    = number of the profile link (readlink <profile>)
  prev = highest existing <profile>-<k>-link with k < N
  none -> "No earlier generation to compare with." exit 0
  else -> dix <profile>-<prev>-link <profile>-<N>-link
          "Changes from generation <prev> to <N>:"
```
Only `staged != current` decides "pending", not `staged != booted`. After
`nixos-central-upgrade` the new generation is already running and it is no
longer pending; a kernel change still waits for the reboot, but that's what
`upgrade` already prints. During `nixos-central-try`, current ≠ staged, so the
diff shows "tried → default boot entry", which is exactly what a reboot does.
The header then says "Pending on next reboot" without the word "update", so
it isn't misleading.

The highest number below N (not N-1) handles generations removed by GC. After a
`--rollback` the profile points to an older generation; "previous" is then
relative to that, and the header numbers make it visible.

### Reboot notification
Body becomes "A system update has been installed and will be used after the
next reboot. Run nixos-central-diff to see what it changes." Title unchanged, so
existing tests that look for it keep working.

### Reboot-notification tests: minimal in `nix flake check`, desktops opt-in
`reboot-notify-kde`/`-gnome` boot full desktops (about 10–15 minutes each) on
every `nix flake check`. They are split up:
- `checks.reboot-notify`: `desktop = "none"`, with a small Gio stub that owns
  `org.freedesktop.Notifications` on the user's session bus and logs every
  title and body. It checks the notification logic (once per generation,
  nothing after reboot, the text). Headless machines never reach
  `graphical-session.target`, so it starts the service directly instead of
  waiting for the timer.
- `legacyPackages.x86_64-linux.desktopTests.reboot-notify-{kde,gnome}`: the
  unchanged desktop tests, which check that the timer and the desktop's own
  notification server work in a real session. They run on demand
  (`nix build .#desktopTests.reboot-notify-kde`), not in `nix flake check` and
  so not in CI.

For the minimal test the module needs to work with `desktop = "none"`. It is
gated by an internal option `nixos-central.rebootNotify.enable` (default
`desktop != "none"`, so machines behave as before). *Alternatives:* lifting the
notifier script out of another host's config (it would test the script, not the
module); making the user service unconditional (adds a dead unit to every
headless machine). `legacyPackages` is used because `nix flake check` doesn't
build it and `nix build .#<name>` finds it without the system prefix.

## Risks / Trade-offs

- [Large diffs on nixpkgs bumps scroll off the screen] → dix's output is a
  plain list; users can pipe to `less`. No pager is built in.
- [Paths of a previous generation not present, e.g. a profile link to a
  collected path] → Can't happen with GC roots: every `*-link` keeps its closure.
  If `dix` fails anyway, its error and exit code pass through.
- [dix output format changes between nixpkgs releases] → Tests only check for
  package names, not layout.

## Open Questions

None.
