# nixos-central diff: what the staged update (or else the last one) changes.
{ pkgs, ... }:
{
  nixos-central.commands.diff =
    (import ../../nixos-central-internal/command/subcommands.nix).diff
    // {
      package = pkgs.callPackage ../../nixos-central-internal/diff { mode = "system"; };
    };
}
