# Docker daemon on every machine, usable by the primary user without sudo.
# Members of the docker group can run containers as root, so the group is as
# privileged as wheel.
{ config, ... }:
{
  virtualisation.docker.enable = true;
  users.users.${config.nixos-central.user}.extraGroups = [ "docker" ];
}
