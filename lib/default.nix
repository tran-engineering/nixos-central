{ inputs }:
let
  inherit (inputs) nixpkgs home-manager disko;
  inherit (nixpkgs) lib;

  # All NixOS modules of a machine, without evaluating them (also used by tests).
  hostModules =
    {
      hostname,
      user,
      desktop,
      disk,
      stateVersion,
      modules ? [ ],
      system ? "x86_64-linux",
    }:
    [
      disko.nixosModules.disko
      home-manager.nixosModules.home-manager
      ../modules/options.nix
      ../disko
      ../modules/base
      ../modules/desktops.nix
      ../modules/user.nix
      {
        nixpkgs.hostPlatform = system;
        system.stateVersion = stateVersion;
        nixos-central = {
          inherit
            hostname
            user
            desktop
            disk
            ;
        };
      }
    ]
    ++ modules;
in
{
  inherit hostModules;

  desktopNames = import ./desktop-names.nix;

  # NixOS release of the pinned nixpkgs, e.g. "26.05". The installer writes it
  # into new machine flakes as their stateVersion.
  release = lib.trivial.release;

  # Build a complete machine from its facts. This is the only interface machine
  # flakes depend on; keep it backwards compatible.
  mkHost =
    args:
    lib.nixosSystem {
      specialArgs = { inherit inputs; };
      modules = hostModules args;
    };
}
