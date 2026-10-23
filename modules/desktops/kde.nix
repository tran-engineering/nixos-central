# KDE Plasma 6 on Wayland with SDDM.
{ config, lib, ... }:
{
  config = lib.mkIf (config.nixos-central.desktop == "kde") {
    services.desktopManager.plasma6.enable = true;
    services.displayManager.sddm = {
      enable = true;
      wayland.enable = true;
    };

    services.pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
    };
    security.rtkit.enable = true;

    hardware.bluetooth.enable = true;
    services.printing.enable = true;
  };
}
