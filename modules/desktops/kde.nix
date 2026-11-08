# KDE Plasma 6 on Wayland (login screen: GDM, modules/base/graphical.nix).
{ config, lib, ... }:
{
  config = lib.mkIf (config.nixos-central.desktop == "kde") {
    services.desktopManager.plasma6.enable = true;
  };
}
