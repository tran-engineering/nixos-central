# Design

## Context

`nixos-central-internal/disko/default.nix` defines the disk layout. `hostModules` (`nixos-central-internal/lib/default.nix`) imports it into every machine. The installer runs it through `disko --mode destroy,format,mount`, and on the installed system it generates `fileSystems`/`boot.initrd.luks`. `nixos-generate-config` runs with `--no-filesystems`, so the disko module is the only place mounts are defined. Everything except the innermost `content` block (GPT, ESP, LUKS `cryptroot`, key file `/tmp/nixos-central-luks.key`) stays as it is.

## Goals / Non-Goals

**Goals:**
- Replace the btrfs content of the LUKS container with one ext4 filesystem at `/`.
- Leave `install.sh`, the machine flake format, and the LUKS settings untouched.

**Non-Goals:**
- A compatibility path for btrfs machines. The user confirmed none are installed.
- Swap, LVM, or a separate `/home` partition.
- Changing TRIM behavior beyond what exists today.

## Decisions

- **ext4 directly inside LUKS, no LVM.** This is the smallest layout that meets the request. The alternative was LUKS + LVM with separate `/` and `/home`, which would let a reinstall keep `/home`. The user chose the single-root layout.
- **Disko `filesystem` content type**: `type = "filesystem"; format = "ext4"; mountpoint = "/"; mountOptions = [ "noatime" ];`. This mirrors how the ESP is declared. `noatime` stays because the btrfs layout used it and it saves writes. `compress=zstd` has no ext4 equivalent and is dropped.
- **No `extraArgs`.** The btrfs block used `-f` to force mkfs over old signatures. disko's `destroy` mode already wipes the disk before formatting, and the new LUKS container is fresh, so `mkfs.ext4` sees no existing filesystem. If e2e shows mkfs.ext4 prompting, add `extraArgs = [ "-F" ]`.
- **Keep `settings.allowDiscards = true` on LUKS.** TRIM still reaches the device. Periodic trimming relies on the NixOS default for `services.fstrim.enable`. The repo does not set it, and that is unchanged here.

## Risks / Trade-offs

- [No transparent compression] → The Nix store uses more space than with zstd btrfs. The installer already requires a disk of at least 40 GiB, and garbage collection limits store growth.
- [A machine installed with btrfs after all would fail to mount `/` after an upgrade] → The user confirmed none exist. The proposal flags the change as breaking for such machines.
- [ext4 reserves 5% of blocks for root by default] → This is accepted, because it protects the system when the disk fills up.

## Migration Plan

None needed, because there are no installed machines. Rollback means reverting the commit. Machines installed with ext4 in the meantime would then need reinstalling, which is the same situation in reverse.
