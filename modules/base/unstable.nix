# pkgs.unstable: packages from the nixpkgs-unstable input, with the same
# nixpkgs config (e.g. allowUnfree). Lazy: only evaluated when something uses it.
# Ad-hoc shells (registry, NIX_PATH) stay on the stable nixpkgs.
{ config, inputs, ... }:
{
  nixpkgs.overlays = [
    (final: _: {
      unstable = import inputs.nixpkgs-unstable {
        inherit (final.stdenv.hostPlatform) system;
        inherit (config.nixpkgs) config;
      };
    })
  ];
}
