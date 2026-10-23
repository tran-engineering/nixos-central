# Stand-in for hardware-configuration.nix on CI sample hosts (QEMU guest).
{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];
}
