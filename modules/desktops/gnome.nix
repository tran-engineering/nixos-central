# GNOME on Wayland with GDM.
{ config, lib, pkgs, ... }:
{
  config = lib.mkIf (config.nixos-central.desktop == "gnome") {
    services.desktopManager.gnome.enable = true;
    services.displayManager.gdm.enable = true;

    # Firmware updates (modules/base/fwupd.nix) in a window; GNOME Software,
    # which would list them, is only installed together with flatpak.
    environment.systemPackages = [ pkgs.gnome-firmware ];
  };
}
