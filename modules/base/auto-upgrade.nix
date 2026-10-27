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

  # Record every successful run, also when nothing changed, for the update notice
  # (modules/home/update-notice.nix). postStart only runs if the upgrade succeeded.
  systemd.services.nixos-upgrade.postStart = ''
    mkdir -p /var/lib/nixos-central
    touch /var/lib/nixos-central/last-update
  '';
}
