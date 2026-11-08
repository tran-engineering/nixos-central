# nixos-central-internal

Everything behind nixos-central that is not part of customizing a machine.
You do not need to read or edit this folder to add a package, change a desktop
or change the base configuration every user gets; those live in `modules/` at
the top level. Personal profiles live in private overlays.

| Path | What it is |
|---|---|
| `installer/install.sh` | The `curl … \| sh` installer. Published to GitHub Pages by `.github/workflows/pages.yml`. |
| `lib/` | `lib.mkHost`, the entry point machine flakes call, and the list of modules every machine gets. `desktop-names.nix` lists the desktops by reading `modules/desktops/`. |
| `disko/` | Disk layout (GPT, EFI partition, encrypted ext4) shared by all machines. |
| `templates/host/` | Flake template the installer renders into `/etc/nixos` on a new machine. |
| `tests/` | VM tests run by `nix flake check`, the stand-in hardware file for CI sample hosts, the test profiles `tests/profiles/` (only CI configurations use them), and `tests/e2e`, a full installer test in QEMU. |
