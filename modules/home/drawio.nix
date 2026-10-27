# Shared home module: draw.io diagram editor. Opt in from a profile with
#   imports = [ ../../modules/home/drawio.nix ];
{ pkgs, ... }:
{
  home.packages = [ pkgs.drawio ];
}
