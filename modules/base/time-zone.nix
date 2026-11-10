# The machine's time zone (fact set by the installer, default Europe/Zurich).
# A default only, so a machine's own modules may set another one. The clock is
# synced by NixOS' default NTP client (systemd-timesyncd).
{ config, lib, ... }:
{
  time.timeZone = lib.mkDefault config.nixos-central.timeZone;
}
