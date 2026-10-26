# Daily: bump the `central` input (and the private overlay, if any) in
# /etc/nixos and stage the result as the next boot entry. The running system is
# never touched and never rebooted.
{ config, ... }:
{
  system.autoUpgrade = {
    enable = true;
    flake = "/etc/nixos";
    flags = import ./central-update-flags.nix config;
    upgrade = false; # channels only; we have none
    operation = "boot";
    allowReboot = false;
    dates = "daily";
    persistent = true;
    randomizedDelaySec = "30min";
  };
}
