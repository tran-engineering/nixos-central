# nixos-central-diff: what the staged update (or else the last one) changes.
{ pkgs, ... }:
{
  environment.systemPackages = [
    (pkgs.callPackage ../../nixos-central-internal/diff { mode = "system"; })
  ];
}
