# End-to-end installer test in QEMU (UEFI, KVM, internet access required).
#
#   nix run --impure -f nixos-central-internal/tests/e2e
#
# Boots the published installation image (packages.x86_64-linux.iso, same
# modules plus a serial console), installs via
# nixos-central-internal/installer/install.sh against a local git copy of this
# repo, reboots into the installed system and exercises updates and
# nixos-central-try.
let
  flake = builtins.getFlake (toString ../../..);
  inherit (flake.inputs) nixpkgs;
  pkgs = nixpkgs.legacyPackages.x86_64-linux;

  iso =
    (nixpkgs.lib.nixosSystem {
      # Keep in sync with packages.x86_64-linux.iso in flake.nix; only the
      # serial console is test-specific.
      modules = [
        ../../iso
        { nixpkgs.hostPlatform = "x86_64-linux"; }
        { boot.kernelParams = [ "console=ttyS0,115200" ]; }
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
      --repo "${toString ../../..}" \
      --iso "$(echo ${iso}/iso/*.iso)" \
      --ovmf "${pkgs.OVMF.fd}/FV" \
      "$@"
  '';
}
