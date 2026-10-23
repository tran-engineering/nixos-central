# nixos-central-internal

Everything behind nixos-central that is not part of customizing a machine.
You do not need to read or edit this folder to add a package, change a desktop
or set up a user profile; those live in `modules/` and `users/` at the top level.

| Path | What it is |
|---|---|
| `installer/install.sh` | The `curl … \| sh` installer. Published to GitHub Pages by `.github/workflows/pages.yml`. |
| `lib/` | `lib.mkHost`, the entry point machine flakes call, and the list of modules every machine gets. `desktop-names.nix` lists the desktops by reading `modules/desktops/`. |
| `disko/` | Disk layout (GPT, EFI partition, encrypted btrfs) shared by all machines. |
| `templates/host/` | Flake template the installer renders into `/etc/nixos` on a new machine. |
| `tests/` | VM tests run by `nix flake check`, the stand-in hardware file for CI sample hosts, and `tests/e2e`, a full installer test in QEMU. |
