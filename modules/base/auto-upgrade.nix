# Daily: bump the `central` input in /etc/nixos and stage the result as the
# next boot entry. The running system is never touched and never rebooted.
{ ... }:
{
  system.autoUpgrade = {
    enable = true;
    flake = "/etc/nixos";
    flags = [
      "--update-input"
      "central"
    ];
    upgrade = false; # channels only; we have none
    operation = "boot";
    allowReboot = false;
    dates = "daily";
    persistent = true;
    randomizedDelaySec = "30min";
  };
}
