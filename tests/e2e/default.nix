# End-to-end installer test in QEMU (UEFI, KVM, internet access required).
#
#   nix run --impure -f tests/e2e
#
# Boots a NixOS minimal installer image (plus serial console), installs via
# installer/install.sh against a local git copy of this repo, reboots into the
# installed system and exercises updates and nixos-central-try.
let
  flake = builtins.getFlake (toString ../..);
  inherit (flake.inputs) nixpkgs;
  pkgs = nixpkgs.legacyPackages.x86_64-linux;

  iso =
    (nixpkgs.lib.nixosSystem {
      modules = [
        "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
        {
          nixpkgs.hostPlatform = "x86_64-linux";
          boot.kernelParams = [ "console=ttyS0,115200" ];
          isoImage.squashfsCompression = "zstd -Xcompression-level 3";
        }
      ];
    }).config.system.build.isoImage;
in
pkgs.writeShellApplication {
  name = "nixos-central-e2e";
  runtimeInputs = [
    (pkgs.python3.withPackages (p: [ p.pexpect ]))
    pkgs.qemu_kvm
    pkgs.git
    pkgs.rsync
  ];
  text = ''
    exec python3 ${./run.py} \
      --repo "${toString ../..}" \
      --iso "$(echo ${iso}/iso/*.iso)" \
      --ovmf "${pkgs.OVMF.fd}/FV" \
      "$@"
  '';
}
