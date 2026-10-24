# GNOME on Wayland with GDM.
{ config, lib, ... }:
{
  config = lib.mkIf (config.nixos-central.desktop == "gnome") {
    services.desktopManager.gnome.enable = true;
    services.displayManager.gdm.enable = true;
  };
}
