# GNOME on Wayland with GDM.
{ config, lib, pkgs, ... }:
{
  config = lib.mkIf (config.nixos-central.desktop == "gnome") {
    services.desktopManager.gnome.enable = true;
    services.displayManager.gdm.enable = true;

    # Firmware updates (modules/base/fwupd.nix) in a window. GNOME Software
    # lists them too (nixpkgs installs it with Flatpak, modules/base/flatpak.nix);
    # kept because users know this app.
    environment.systemPackages = [ pkgs.gnome-firmware ];
  };
}
