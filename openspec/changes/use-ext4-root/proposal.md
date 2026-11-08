# Proposal

## Why

The installer formats the encrypted root as btrfs with subvolumes (`@`, `@home`, `@nix`) and zstd compression. Nothing in nixos-central uses btrfs features: there are no snapshots, no snapper, and no send/receive. A single ext4 filesystem is simpler, better understood, and easier to repair. No machine has been installed with the btrfs layout yet, so the layout can change now without a migration path.

## What Changes

- Change the shared disk layout to a 1 GiB EFI system partition (unchanged) plus a LUKS container (unchanged: `cryptroot`, discards allowed) that holds **one ext4 filesystem mounted at `/`**. `/home` and `/nix` become ordinary directories on it.
- Remove the btrfs subvolumes and the `compress=zstd` mount option. Keep `noatime` on the ext4 root.
- Update the README install steps and `nixos-central-internal/README.md` so they describe the ext4 layout.
- Extend the end-to-end test to check that the installed root is ext4 on the LUKS mapping.
- Note: this would be **BREAKING** for any machine already installed with btrfs, because every machine gets its `fileSystems` from this shared layout. The user confirmed that no such machines exist, so the change adds no compatibility option.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `installer`: the "Disk is encrypted with a prompted passphrase" requirement now specifies that the encrypted root holds a single ext4 filesystem.

## Impact

- `nixos-central-internal/disko/default.nix`: the layout every machine uses, both for formatting during install and for the generated `fileSystems`.
- `README.md` (install step 6) and `nixos-central-internal/README.md` (the `disko/` row).
- `nixos-central-internal/tests/e2e/run.py`: the installed-system phase.
- No change to `install.sh`, the machine flake, or the `mkHost` entry point. The LUKS key file path and the GPT partition labels stay the same.
