# Tailscale daemon on every machine. It stays idle until someone signs in with
# `tailscale up`, which the primary user may run without sudo. The sign-in is
# machine state (/var/lib/tailscale), never part of a repository.
{ config, ... }:
{
  services.tailscale = {
    enable = true;
    extraSetFlags = [ "--operator=${config.nixos-central.user}" ];
  };
}
