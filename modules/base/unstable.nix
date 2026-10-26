# pkgs.unstable: packages from the nixpkgs-unstable input, with the same
# nixpkgs config (e.g. allowUnfree). Lazy: only evaluated when something uses it.
# Ad-hoc shells (registry, NIX_PATH) stay on the stable nixpkgs.
{ config, inputs, ... }:
let
  shared = import ../../nixos-central-internal/lib/nixpkgs.nix { inherit inputs; };
in
{
  nixpkgs.overlays = [ (shared.unstableOverlay config.nixpkgs.config) ];
}
