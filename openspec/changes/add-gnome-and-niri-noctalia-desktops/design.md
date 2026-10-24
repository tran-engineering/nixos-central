# Design

## Context

- Desktops are `modules/desktops/<name>.nix`, each wrapped in `lib.mkIf (config.nixos-central.desktop == "<name>")`. `nixos-central-internal/lib/desktop-names.nix` lists the regular `*.nix` files in that directory (subdirectories are ignored). The option type, the installer's desktop prompt and `modules/desktops.nix` all derive from that list, so a new file is enough to offer a new desktop.
- `kde.nix` currently also enables PipeWire, rtkit, Bluetooth and printing.
- `modules/base/reboot-notify.nix` is enabled for every desktop except `none` and needs a notification server in the session. The `reboot-notify` VM test covers only KDE, and it waits for `plasmashell`.
- home-manager runs with `useGlobalPkgs = true`, so overlays on the system `pkgs` are visible in profiles.
- Facts from the pinned inputs, checked while writing this design:
  - nixos-26.05 has niri 26.04, `noctalia-shell` 4.7.6 (wraps quickshell; runtime deps brightnessctl, cliphist, ddcutil, wlsunset and bluez on PATH) and GNOME 50.5.
  - nixpkgs has a `programs.niri` module, which registers the session, sets up portals and enables gnome-keyring. nixpkgs has no Noctalia module, and neither does home-manager release-26.05.
  - The niri binary reads `/etc/niri/config.kdl` as a fallback config path.
  - nixpkgs has no niri VM test.

## Goals / Non-Goals

**Goals:**
- `gnome` and `niri-noctalia` that are usable after install without extra configuration.
- niri and Noctalia from stable nixos-26.05 (see D8).
- `pkgs.unstable` for profiles.

**Non-Goals:**
- Per-user Noctalia settings (themes, bar layout) beyond Noctalia's own defaults. Users change them in Noctalia's settings UI, which writes to `~/.config/noctalia`.
- Other niri shells or other niri variants.
- Changing the installer's suggested default (stays `kde`).
- A Noctalia home-manager module or the upstream Noctalia flake.

## Decisions

### D1: `nixpkgs-unstable` input tracks `nixos-unstable`
`inputs.nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable"`. The `nixos-unstable` branch only advances after the NixOS tests pass on Hydra, which is safer than `nixpkgs-unstable`. home-manager and disko keep following stable `nixpkgs`. The weekly `flake.lock` workflow already updates every input, so it bumps unstable too. CI builds the PR before machines see it.

### D2: `pkgs.unstable` via an overlay in the base
A new `modules/base/unstable.nix` adds
`nixpkgs.overlays = [ (final: _: { unstable = import inputs.nixpkgs-unstable { inherit (final.stdenv.hostPlatform) system; config = config.nixpkgs.config; }; }) ]`.
Passing `config.nixpkgs.config` carries `allowUnfree` over. The import is lazy: machines that never touch `pkgs.unstable` evaluate no second nixpkgs, although they still lock the input. The nix registry and `NIX_PATH` stay on stable, so ad-hoc shells are unaffected.
*Alternative:* pass `inputs.nixpkgs-unstable` via `specialArgs` and import it where needed. Rejected: profiles would need `extraSpecialArgs` wiring, and each import site would have to repeat the config.

### D3: Shared graphical module
New `modules/base/graphical.nix`, enabled when `desktop != "none"`, takes PipeWire (alsa, pulse), rtkit, Bluetooth and printing out of `kde.nix`. KDE keeps only Plasma and SDDM. GNOME's module also enables PipeWire, and those values merge without conflict.
*Alternative:* duplicate the blocks per desktop. Rejected: three copies that would drift apart.

### D4: `gnome`
`services.desktopManager.gnome.enable` plus `services.displayManager.gdm.enable` (Wayland is the default). Nothing else. GNOME brings its own notification server, keyring, portals and power management.

### D5: `niri-noctalia`
- `programs.niri.enable = true` (stable niri; D8).
- `services.displayManager.sddm = { enable = true; wayland.enable = true; }` and `services.displayManager.defaultSession = "niri"`. `security.pam.services.sddm.enableGnomeKeyring = true`, so the keyring the niri module enables is unlocked at login.
- A Noctalia **systemd user service** `noctalia-shell`, which is `wantedBy`/`partOf` `graphical-session.target` and runs `lib.getExe pkgs.noctalia-shell` with `Restart = "on-failure"`. niri's session activates `graphical-session.target`. Noctalia starts this way even with a user's own niri config, where `spawn-at-startup` would be lost. The only session on these machines is niri, so the service needs no condition.
- Services that Noctalia's widgets use: `services.upower.enable` (battery) and `services.power-profiles-daemon.enable` (power profiles). NetworkManager and Bluetooth are already enabled.
- Desktop basics that niri lacks:
  - a polkit agent: `polkit_gnome` as a user service bound to `graphical-session.target`
  - `xwayland-satellite`, which niri spawns on demand for X11 apps
  - `alacritty` as the terminal
  - Nautilus, which the niri module already uses for the file chooser

### D6: Central niri config at `/etc/niri/config.kdl`
The config file is `modules/desktops/niri-noctalia/config.kdl`. A subdirectory, so `desktop-names.nix` ignores it. It is installed with `environment.etc."niri/config.kdl"`. niri reads `$NIRI_CONFIG` first, then `~/.config/niri/config.kdl`, then `/etc/niri/config.kdl`, so a profile that writes `xdg.configFile."niri/config.kdl"` takes precedence.
The file starts from the packaged niri version's `resources/default-config.kdl`, with these changes:
- `Mod+D` → `noctalia-shell ipc call launcher toggle`
- the lock binding → `noctalia-shell ipc call lockScreen lock`
- media, volume and brightness keys → Noctalia IPC calls, so its on-screen display shows
- any `waybar` spawn removed

Checked against Noctalia 4.7.6: `launcher toggle`, `lockScreen lock`, `volume increase|decrease|muteOutput|muteInput`, `brightness increase|decrease`, `media playPause|next|previous`, `sessionMenu toggle` (power menu).
The file is installed through a `runCommand` that runs `niri validate -c` with the niri package in use, so a niri update that breaks the config fails the build, not a login.
*Alternative:* ship the config through home-manager in `users/_default`. Rejected: users with a personal profile that doesn't import `_default` would get niri's built-in default (fuzzel, waybar, which aren't installed) and no Noctalia bindings.

### D7: Tests
- `flake.nix` sample hosts `ci-gnome` and `ci-niri-noctalia`. These become the `host-*` checks.
- The `reboot-notify` test becomes a function of the desktop, generating `reboot-notify-kde`, `reboot-notify-gnome` and `reboot-notify-niri-noctalia`. Each uses auto-login (`services.displayManager.autoLogin`, which works for SDDM and GDM). Instead of `pgrep plasmashell`, each waits until `org.freedesktop.Notifications` is owned on alice's session bus. The notification logic is unchanged.
- `reboot-notify-niri-noctalia` additionally checks:
  - `noctalia-shell` is active
  - niri runs with `/etc/niri/config.kdl` and has not created `~/.config/niri/config.kdl`
  - an `Mod+D`-equivalent IPC call (`noctalia-shell ipc call launcher toggle` as alice) succeeds

### D8: niri and Noctalia from stable (changed during implementation)
The plan was to take both from `pkgs.unstable`. At the locked nixos-unstable revision (2026-10-20), `noctalia-shell` 4.7.7 does not build: its quickshell fork `noctalia-qs` 0.0.12 fails against Qt 6.12 ("Meta Types must be fully defined"), and Hydra has no cached build. niri is 26.04 in both branches. So both come from nixos-26.05 (niri 26.04, Noctalia 4.7.6). Moving them back is a one-line change per package (`pkgs.unstable.niri` for `programs.niri.package`, `pkgs.unstable.noctalia-shell` in the service) once unstable builds.
*Alternatives considered:* pinning unstable to an older revision (the weekly lock update would break CI again), a manual stable/unstable switch, patching `noctalia-qs` in an overlay (maintenance burden for a problem nixpkgs will fix).

## Risks / Trade-offs

- [niri in a QEMU VM without a GPU may fail to render (no niri VM test exists in nixpkgs)] → Plasma already runs in the VM tests on mesa llvmpipe. If niri still fails, the test VM switches to `-device virtio-gpu-pci`. If that fails too, the niri test is reduced to checking the session's services and IPC, and that limitation is recorded in tasks.md.
- [A nixpkgs update breaks niri/Noctalia or their compatibility] → the weekly lock PR is built in CI, including `niri validate` and the VM test, before machines get it. Rollback via boot menu as for any update.
- [Every machine fetches the nixpkgs-unstable source to evaluate] → accepted. Only profiles using `pkgs.unstable` download unstable packages.
- [CI time and disk: three desktop VM tests instead of one] → runner disk is already freed. If the time becomes a problem, the GNOME and niri tests can move to a separate job.
- [Noctalia IPC names or config layout change between versions] → validated at build time (config) and in the VM test (IPC).
- [Users switching an existing machine from `kde` to `niri-noctalia` keep KDE's dotfiles] → harmless; nothing to migrate.

## Migration Plan

Additive for existing machines (`kde`, `none`): the KDE module refactor (D3) produces the same services. To change desktops, users edit `desktop` in `/etc/nixos/flake.nix` and run `sudo nixos-rebuild switch --flake /etc/nixos`, then reboot so the login screen changes. Rollback: the previous generation in the boot menu.
