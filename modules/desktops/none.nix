# No graphical desktop: console login only.
{ config, lib, ... }:
{
  config = lib.mkIf (config.nixos-central.desktop == "none") { };
}
