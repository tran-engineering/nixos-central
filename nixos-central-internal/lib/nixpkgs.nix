# nixpkgs settings shared by NixOS machines (modules/base) and standalone
# homes (lib.mkHome), so both see the same package set.
{ inputs }:
{
  config = {
    allowUnfree = true;
  };

  # pkgs.unstable: packages from the nixpkgs-unstable input, with the given
  # nixpkgs config. Lazy: only evaluated when something uses it.
  unstableOverlay =
    nixpkgsConfig: final: _: {
      unstable = import inputs.nixpkgs-unstable {
        inherit (final.stdenv.hostPlatform) system;
        config = nixpkgsConfig;
      };
    };
}
