# Part of every profile (NixOS: modules/user.nix, standalone: lib.mkHome).
# Set by mkHost/mkHome when the local flake passes a private overlay.
{ lib, ... }:
{
  options.nixos-central.private.enable = lib.mkEnableOption "the private overlay of the local flake";
}
