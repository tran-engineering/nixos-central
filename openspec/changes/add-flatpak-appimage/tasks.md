# Tasks

## 1. Flatpak with Flathub

- [x] 1.1 Add `modules/base/flatpak.nix` with the internal option `nixos-central.desktopApps.enable` (default `config.nixos-central.desktop != "none"`), `services.flatpak.enable`, the vendored `modules/base/flatpak/flathub.flatpakrepo` (copied from `https://dl.flathub.org/repo/flathub.flatpakrepo`) and the oneshot service running `flatpak remote-add --system --if-not-exists flathub <file>`; import it from `modules/base/default.nix`; verify `nix flake check` evaluates all hosts and that a `none` host has no `services.flatpak.enable`
- [x] 1.2 Add the `desktop-apps` VM check in `nixos-central-internal/tests/default.nix` with node `machine` (desktop `none`, `desktopApps.enable = true`) and node `plain` (defaults): `flatpak remotes --system` lists `flathub` offline and the service did not fail; on `plain`, `command -v flatpak` fails; verify `nix build .#checks.x86_64-linux.desktop-apps` passes

## 2. Daily Flatpak updates

- [x] 2.1 In `flatpak.nix`, add the system `flatpak-update.service`/`.timer` (`flatpak update --system --noninteractive --assumeyes`, after and wanting `network-online.target`; `OnStartupSec=5min`, `OnCalendar=daily`, `Persistent=true`, `RandomizedDelaySec=30min`) and the same pair as user units running `flatpak update --user …`, enabled for every user; verify with the check below
- [x] 2.2 Extend the `desktop-apps` check: both timers are enabled and have a startup trigger (system timer via `systemctl is-enabled`, user timer for `alice` after login via `systemctl --user is-enabled`); start the system update service offline, then `flatpak list` and `flatpak remotes --system` still succeed; verify the check passes

## 3. AppImage

- [x] 3.1 Add `modules/base/appimage.nix` setting `programs.appimage = { enable = true; binfmt = true; }` under `nixos-central.desktopApps.enable`, imported from `modules/base/default.nix`; extend the `desktop-apps` check so `/proc/sys/fs/binfmt_misc/appimage_type_1` and `appimage_type_2` exist and are enabled on `machine` and absent on `plain`; verify the check passes

## 4. Desktop integration and documentation

- [x] 4.1 Update the comment in `modules/desktops/gnome.nix` (GNOME Software now comes with Flatpak; `gnome-firmware` kept) and the comment in `modules/base/fwupd.nix`; verify `nix flake check` passes
- [ ] 4.2 README: new section "Installing apps" (Nix packages in a profile first; otherwise Flathub via Discover, GNOME Software or `flatpak install flathub <id>`; `--user` installs need no password; daily automatic updates and how to hold one back with `flatpak mask`; Flatpak apps are not rolled back with a generation and not shown by `nixos-central diff`; AppImages run after `chmod +x`; none of this on desktop `none`), mention GNOME Software in "Firmware updates", and add the new check to the test list in Development; verify every command in the section against a VM from 5.1

## 5. Manual verification on real desktops

- [ ] 5.1 In a KDE and a GNOME VM with network (built from a test host with that desktop): install a Flathub app from Discover and from GNOME Software, start it from the launcher, run `systemctl start flatpak-update.service` and check it succeeds, and start a downloaded AppImage by double-click/`./App.AppImage`; on `niri-noctalia`, install an app with `flatpak install flathub <id>` and start it from the Noctalia launcher; record anything about missing fonts or themes in the README
