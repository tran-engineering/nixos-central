# Tasks

## 1. Image definition

- [ ] 1.1 Add `nixos-central-internal/iso/default.nix` (on top of `installation-cd-minimal.nix`: flakes enabled, zstd squashfs, image name with release) and expose `packages.x86_64-linux.iso` in `flake.nix`; verify `nix build .#packages.x86_64-linux.iso` produces one `.iso` under 2 GiB and `nix flake check` does not build it
- [ ] 1.2 Add `nixos-central-start` (network check with `nmtui` offer, "Install nixos-central on this computer? [Y/n]", then `nix run --refresh "$CENTRAL#installer"` with `CENTRAL` honoring `NIXOS_CENTRAL_FLAKE`; decline leaves a shell with a hint), started from the `nixos` login shell on `/dev/tty1` only; verify with shellcheck, and in QEMU that tty1 shows the prompt and the serial console does not

## 2. Tests

- [ ] 2.1 Make `tests/e2e/default.nix` build the flake's image module list plus the serial console; verify the existing e2e run (`nix run --impure -f nixos-central-internal/tests/e2e`) passes unchanged
- [ ] 2.2 Add an e2e step that runs `nixos-central-start` on the serial console with `NIXOS_CENTRAL_FLAKE` pointing at the test server, and checks that the installer's hostname question appears; also check that declining returns to a shell with nothing installed

## 3. Publishing

- [ ] 3.1 Add `.github/workflows/iso.yml` (dispatch, monthly, pushes touching the image definition): build, 2 GiB size check, `.sha256`, release `iso-<date>` with fixed asset names marked latest, and pruning to the newest three image releases; verify a manual run on a branch publishes a release whose `.sha256` matches the downloaded file
- [ ] 3.2 Point `install.sh`'s "boot the installation image" messages to the latest-image URL; verify with shellcheck and the e2e "not a live image" and BIOS cases

## 4. Documentation

- [ ] 4.1 Rewrite the README Install section around the image (download plus checksum, write to USB, boot in UEFI, answer the prompt, Wi-Fi via the offered `nmtui`), keep the curl one-liner as "Already have a NixOS USB stick?", mention `NIXOS_CENTRAL_FLAKE` for installing a specific revision, and add `nix build .#packages.x86_64-linux.iso` to Development; verify each documented URL resolves after the first release

## Workflow follow-up

- After merge: run the ISO workflow manually once, so the latest-image URL exists before users follow the README.
- Possible follow-up change: keyboard layout selection in the start-up prompt, written to the machine as a fact.
