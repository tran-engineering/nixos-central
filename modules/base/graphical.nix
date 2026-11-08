# Services every graphical desktop gets (all desktops except "none"), including
# the login screen: GDM for every desktop. It shows PAM's prompts, such as the
# security key's "Please touch the device." (modules/base/u2f.nix). It
# suspends the machine after inactivity at the login screen
# (services.displayManager.gdm.autoSuspend).
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

    services.displayManager.gdm.enable = true;
  };
}
