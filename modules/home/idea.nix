# Shared home module: IntelliJ IDEA. Opt in from a profile with
#   imports = [ ../../modules/home/idea.nix ];
{ pkgs, ... }:
{
  home.packages = [ pkgs.jetbrains.idea ];
}
