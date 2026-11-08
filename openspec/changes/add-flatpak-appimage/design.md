# Design

## Context

- Shared services for graphical desktops live in `modules/base/graphical.nix`,
  guarded by `config.nixos-central.desktop != "none"`. `reboot-notify.nix`
  shows a pattern for testing such a feature without a desktop: an internal
  enable option whose default is the desktop condition, which the minimal VM
  test sets itself.
- nixpkgs already does part of the wiring once `services.flatpak.enable` is
  set: Plasma 6 adds `flatpak-kcm` (Discover is already present because fwupd
  is on), and GNOME installs GNOME Software only together with Flatpak.
  `services.flatpak` requires `xdg.portal.enable`, which all three graphical
  desktops already set.
- `services.flatpak` itself adds no remote and does no updates.
- `programs.appimage = { enable; binfmt; }` registers `appimage_type_1` and
  `appimage_type_2` in binfmt_misc with `appimage-run` as the interpreter.
- The primary user is in `wheel`. Flatpak's polkit rules let wheel users
  install system-wide after entering their password.
- VM checks run offline (`nixos-central-internal/tests/default.nix`).

## Goals / Non-Goals

**Goals:**
- Flathub works right after the first boot, also when that boot is offline.
- Flatpak updates run unattended, like the NixOS upgrade, without a reboot.
- Everything except the actual Flathub download can be tested offline in
  `nix flake check`.

**Non-Goals:**
- Declaring Flatpak apps per profile (e.g. nix-flatpak). Can be added later
  as an opt-in home module without changing what this change sets up.
- Flatpak updates in `nixos-central upgrade` or `nixos-central diff`.
- Font and theme integration for Flatpak apps beyond what Flatpak does itself.

## Decisions

### Two base modules with an internal switch
`modules/base/flatpak.nix` and `modules/base/appimage.nix`, imported from
`modules/base/default.nix`. They share one internal option,
`nixos-central.desktopApps.enable`, default
`config.nixos-central.desktop != "none"` (same shape as
`nixos-central.rebootNotify.enable`), declared in `flatpak.nix`.

- *Alternative: put everything into `graphical.nix`.* Rejected: the Flathub
  service and update timers are enough code to warrant their own file and
  comments, like `fwupd.nix` and `docker.nix`.
- *Alternative: guard on the desktop directly.* Rejected: the check would
  then need a full desktop in the VM test, which is too heavy for
  `nix flake check`.

### Flathub added from a vendored `.flatpakrepo` file
The repository ships `flathub.flatpakrepo` (copied from
`https://dl.flathub.org/repo/flathub.flatpakrepo`; it holds the URL and
Flathub's GPG key). A system oneshot service, wanted by `multi-user.target`
and needing only the local filesystem, runs
`flatpak remote-add --system --if-not-exists flathub <store path>`.

- Works offline, so it can run early on every boot, does not need
  `network-online.target` (which would delay the boot), and is checkable in an
  offline VM test.
- `--if-not-exists` makes it idempotent; a user who removed or changed the
  remote keeps their change except that a removed one comes back at the next
  boot. Acceptable: the spec asks that Flathub is always available.
- *Alternative: `remote-add` with the URL.* Rejected: needs network at boot
  and retry logic.
- *Alternative: static remotes in `/etc/flatpak/remotes.d`.* Not chosen
  because it is less documented and not verified with the nixpkgs flatpak
  version; the service is a well-known pattern.
- The vendored file changes only if Flathub rotates its key, which would be a
  visible upstream event.

### Daily updates: one system timer, one user timer
- `flatpak-update.service` (system) runs
  `flatpak update --system --noninteractive --assumeyes`, triggered by
  `flatpak-update.timer`: `OnCalendar=daily`, `Persistent=true`,
  `RandomizedDelaySec=30min` (same values as `system.autoUpgrade`), plus
  `OnStartupSec=5min` for a run after every boot. The service wants and is
  ordered after `network-online.target`; that only affects the service, not
  the boot.
- *Alternative for the run after boot: `wantedBy = multi-user.target` on the
  service.* Rejected: the target would wait for the service and thus for
  `network-online.target`, holding up the boot when offline, and the update
  would compete with the login. `OnStartupSec` (not `OnBootSec`) so the user
  timer counts from the user's first login instead of firing at once when
  that is more than 5 minutes after boot.
- `flatpak-update.service` as a **user** unit runs `flatpak update --user …`
  for per-user installations (`flatpak install --user`), with the same timer
  settings, enabled for all users via `systemd.user.timers`.
- Flatpak deploys new versions atomically and keeps the old one until the
  update completes, so an offline or failed run leaves apps usable (spec:
  "Update without network"). A failed run is retried by the next day's run.
- GNOME Software and Discover may update apps themselves too; Flatpak locks
  the installation, so concurrent runs are safe.
- *Alternative: hook into `nixos-upgrade.service`.* Rejected: a Flatpak
  failure would then fail the NixOS upgrade, and Flatpak updates do not need
  to wait for a reboot.

### AppImage via nixpkgs' module
`programs.appimage = { enable = true; binfmt = true; }` under the same
switch. No custom code.

### GNOME keeps the Firmware app
GNOME Software now also lists firmware updates, but `gnome-firmware` stays to
avoid removing an app users may know; only the outdated comment in
`modules/desktops/gnome.nix` is fixed. The README firmware section mentions
GNOME Software as a second way.

### Tests
A new check `desktop-apps` with two nodes:
- `machine` (desktop `none`, `nixos-central.desktopApps.enable = true`):
  the Flathub service succeeded and `flatpak remotes --system` lists
  `flathub`, offline; both timers are enabled; after starting the system
  update service offline, `flatpak list` and `flatpak remotes` still work;
  `/proc/sys/fs/binfmt_misc/appimage_type_2` exists and is enabled.
- `plain` (desktop `none`, defaults): no `flatpak` command, no AppImage
  binfmt registration.

Installing a real Flathub app, the app stores, and starting a real AppImage
need network and a desktop; they are verified by hand in a desktop VM
(`nix build .#desktopTests.reboot-notify-kde` style VM or a real machine).

## Risks / Trade-offs

- [Flatpak apps are outside Nix: not rolled back, not in `nixos-central diff`,
  not reproducible across machines] → Documented in the README; declarative
  lists are left for a later opt-in module.
- [Updating apps unattended can bring a broken app version] → Same trade-off
  as the daily NixOS upgrade; `flatpak update --commit=<old>` or
  `flatpak mask` lets a user pin, documented briefly in the README.
- [Flatpak apps may not see fonts and cursor themes from Nix] → Out of scope;
  note in the README if it shows up in manual testing.
- [System-wide installs from the CLI ask for the password] → Expected (polkit,
  wheel); `--user` installs need none.
- [Disk use: runtimes are large (hundreds of MB per runtime)] → Nothing is
  installed by default; only users who install apps pay for it. Flatpak data
  under `/var/lib/flatpak` is not touched by Nix garbage collection.
- [Booting an older generation from before this change: `flatpak` is
  missing, apps do not start until the next generation is booted] → Only
  relevant during the rollout; data in `/var/lib/flatpak` and
  `~/.local/share/flatpak` survives.

## Migration Plan

None needed: machines pick up the change with the next daily upgrade and
reboot. Machines on `none` are unchanged. Rolling back means removing the
modules; installed apps stay on disk until the user removes
`/var/lib/flatpak`.
