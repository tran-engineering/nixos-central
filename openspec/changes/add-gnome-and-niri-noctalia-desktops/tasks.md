# Tasks

Decisions from the user: niri uses SDDM; niri and Noctalia come from stable nixos-26.05 (changed from unstable during implementation, design D8); a new nixpkgs-unstable input unstable is exposed to profiles as `pkgs.unstable`; the desktop is named `niri-noctalia`. Assumptions (see design.md): `nixos-unstable` branch, terminal `alacritty`, polkit agent `polkit_gnome`.

## 1. nixpkgs-unstable and `pkgs.unstable`

- [x] 1.1 Add input `nixpkgs-unstable` (`github:NixOS/nixpkgs/nixos-unstable`) to `flake.nix` and lock it (`nix flake lock`); verify `nix flake metadata` lists it and home-manager/disko still follow stable `nixpkgs`
- [x] 1.2 Add `modules/base/unstable.nix` with the `pkgs.unstable` overlay (design D2) and import it in `modules/base/default.nix`; verify `nix eval .#nixosConfigurations.ci-none.pkgs.unstable.hello.version` equals the unstable input's `hello.version`, and `nix eval .#nixosConfigurations.ci-none.pkgs.unstable.config.allowUnfree` is `true`
- [x] 1.3 Verify the stable registry is untouched: the existing `shells` VM test still passes (`nix build .#checks.x86_64-linux.shells`)
- [x] 1.4 Document `pkgs.unstable` in the README's profile section, with an example `home.packages = [ pkgs.unstable.<name> ];`; verify the example evaluates by temporarily adding it to `users/ci-user/default.nix` and checking that the `helix` derivation in `ci-none`'s `home-manager.users.ci-user.home.packages` is the unstable input's (revert afterwards)

## 2. Shared graphical services and GNOME

- [x] 2.1 Add `modules/base/graphical.nix` (PipeWire with alsa/pulse, rtkit, Bluetooth, printing; `mkIf (desktop != "none")`), import it in the base, and remove those settings from `modules/desktops/kde.nix` (design D3); verify `ci-kde`'s system derivation is byte-identical before and after, and `nix eval` of `services.pipewire.enable`, `hardware.bluetooth.enable`, `services.printing.enable` on `ci-kde` is still `true` and on `ci-none` `false`
- [x] 2.2 Add `modules/desktops/gnome.nix` (design D4) and a sample host `ci-gnome` in `flake.nix`; verify `nix build .#checks.x86_64-linux.host-ci-gnome` succeeds and the installer's desktop list (`nix eval --raw .#lib --apply 'l: toString l.desktopNames'`) includes `gnome`
- [x] 2.3 Turn the `reboot-notify` VM test into one test per graphical desktop (`reboot-notify-kde`, `reboot-notify-gnome`), waiting for `org.freedesktop.Notifications` on alice's session bus instead of `plasmashell` (design D7); verify both pass with `nix build .#checks.x86_64-linux.reboot-notify-kde .#checks.x86_64-linux.reboot-notify-gnome`
- [x] 2.4 Add `gnome` to the README desktop table and `ci-gnome` to the CI sample hosts list; verify the table names match `desktopNames`

## 3. niri with Noctalia

- [x] 3.1 Add `modules/desktops/niri-noctalia.nix` (design D5): niri, SDDM Wayland with default session `niri`, keyring PAM, `noctalia-shell` and polkit-agent user services, upower, power-profiles-daemon, xwayland-satellite, alacritty; add sample host `ci-niri-noctalia`; verify `nix build .#checks.x86_64-linux.host-ci-niri-noctalia` succeeds
- [x] 3.2 Check the Noctalia IPC targets of the packaged version (`noctalia-shell ipc show` in a session, or the shell's IPC sources in the package) for launcher toggle, lock screen, volume, brightness and media; record the names used in design.md D6 if they differ from the assumed `launcher toggle` / `lockScreen lock`
- [x] 3.3 Add `modules/desktops/niri-noctalia/config.kdl` based on the packaged niri's `resources/default-config.kdl` with the D6 changes, installed as `/etc/niri/config.kdl` through a `niri validate -c` build step; verify the build fails when the file is deliberately broken (temporarily) and succeeds when it is restored
- [ ] 3.4 Add `reboot-notify-niri-noctalia` with the extra niri checks from design D7 (noctalia-shell active, `/etc/niri/config.kdl` used, no `~/.config/niri/config.kdl` created, launcher IPC call succeeds), plus a subtest where alice has her own `~/.config/niri/config.kdl` (written via `home-manager.users.alice.xdg.configFile` in the test node) and Noctalia is still active; verify with `nix build .#checks.x86_64-linux.reboot-notify-niri-noctalia`. If niri cannot render in the VM, apply the D-risk fallback (virtio-gpu) and, if still failing, pause and report before reducing the test
  - Deferred by the user (the VM test is slow); the test is not in `tests/default.nix`. One unplanned run (2026-10-24) showed niri renders in QEMU (graphical session up in ~3 s), but no notification server appeared within 900 s, and Noctalia could not run `sh` because of the minimal default service PATH. The PATH is fixed (`enableDefaultPath = false`); whether that also fixes the notification server is unverified.
- [x] 3.5 Add `niri-noctalia` to the README desktop table (niri, Noctalia shell, SDDM) with the main keybindings and how a profile can provide its own `~/.config/niri/config.kdl`; add `ci-niri-noctalia` to the CI sample hosts list; verify the documented keybindings match `config.kdl`

## 4. Integration

- [x] 4.1 Run `nix flake check -L` and verify all checks pass (sample hosts for all four desktops, all VM tests)
- [x] 4.2 Verify the installer offers all four desktops without a hard-coded list: `nix eval --raw .#lib --apply 'l: toString l.desktopNames'` prints `gnome kde niri-noctalia none` (in some order) and `grep -n desktopNames nixos-central-internal/installer/install.sh` shows the installer reads that value (the e2e test stays on `none`, as it has no graphics)
