# Shared home module: the Godot game engine (from nixos-unstable). Opt in from
# a profile with
#   imports = [ ../../modules/home/godot.nix ];
{ pkgs, ... }:
{
  home.packages = [ pkgs.unstable.godot ];
}
