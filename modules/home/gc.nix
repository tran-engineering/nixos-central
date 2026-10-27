# Part of every profile (NixOS: modules/user.nix, standalone: lib.mkHome).
# Weekly: delete the user's generations (home-manager, nix profile) older than
# 30 days, then collect garbage. Root's collection on NixOS
# (modules/base/gc.nix) doesn't reach the user's profiles. The active home is
# always the newest generation, so plain --delete-older-than keeps the rollback
# target. Profiles can override, e.g. nix.gc.options = "--delete-older-than 90d";
{ lib, ... }:
{
  nix.gc = {
    automatic = lib.mkDefault true;
    dates = lib.mkDefault "weekly";
    persistent = lib.mkDefault true;
    randomizedDelaySec = lib.mkDefault "1h";
    options = lib.mkDefault "--delete-older-than 30d";
  };
}
