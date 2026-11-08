# Tasks

## 1. Disk layout

- [x] 1.1 In `nixos-central-internal/disko/default.nix`, replace the btrfs `content` inside the `cryptroot` LUKS container with `type = "filesystem"; format = "ext4"; mountpoint = "/"; mountOptions = [ "noatime" ];`. Update the header comment to "rest LUKS-encrypted ext4". Verify that `nix eval .#nixosConfigurations.<sample-host>.config.fileSystems."/".fsType` (or the equivalent for a CI sample host) prints `"ext4"` and that `fileSystems` has no `/home` or `/nix` entries.
- [x] 1.2 Run `nix flake check -L` and verify that it passes, i.e. sample hosts still evaluate and build and the VM tests pass.

## 2. Tests and documentation

- [x] 2.1 In `nixos-central-internal/tests/e2e/run.py` `phase_installed`, add checks that `findmnt -no FSTYPE,SOURCE /` reports `ext4` on `/dev/mapper/cryptroot`, and that `/home` and `/nix` are not separate mounts (`findmnt -no TARGET -T /nix` and `-T /home` both print `/`). Verify with `nix run --impure -f nixos-central-internal/tests/e2e`. If `mkfs.ext4` asks for confirmation during formatting, add `extraArgs = [ "-F" ]` to the disko filesystem and rerun.
- [x] 2.2 Update `README.md` install step 6 to "the rest LUKS-encrypted ext4", removing the subvolume list, and update the `disko/` row in `nixos-central-internal/README.md` to "encrypted ext4". Verify that `grep -rni btrfs --exclude-dir=.git --exclude-dir=archive .` finds no hits outside `openspec/changes/use-ext4-root/`.
