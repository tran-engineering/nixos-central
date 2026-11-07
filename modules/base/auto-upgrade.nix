# Daily: bump the `central` input (and the private overlay, if any) in
# /etc/nixos and stage the result as the next boot entry. The running system is
# never touched and never rebooted.
{ config, lib, ... }:
{
  system.autoUpgrade = {
    enable = true;
    flake = "/etc/nixos";
    upgrade = false; # channels only; we have none
    operation = "boot";
    allowReboot = false;
    dates = "daily";
    persistent = true;
    randomizedDelaySec = "30min";
  };

  # Bump the inputs before the stock script runs nixos-rebuild. A failure here
  # fails the unit before anything is built. `nix` is on the unit's path.
  systemd.services.nixos-upgrade.preStart = ''
    nix flake update ${lib.escapeShellArgs (import ./central-update-inputs.nix config)} --flake /etc/nixos --refresh
  '';

  # Record every successful run, also when nothing changed, for the update notice
  # (modules/home/update-notice.nix). postStart only runs if the upgrade succeeded.
  systemd.services.nixos-upgrade.postStart = ''
    mkdir -p /var/lib/nixos-central
    touch /var/lib/nixos-central/last-update
  '';
}
