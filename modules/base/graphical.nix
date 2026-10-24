# Services every graphical desktop gets (all desktops except "none").
{ config, lib, ... }:
{
  config = lib.mkIf (config.nixos-central.desktop != "none") {
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
