# Shared base configuration for every machine.
{ config, inputs, ... }:
{
  imports = [
    ./auto-upgrade.nix
    ./gc.nix
    ./reboot-notify.nix
    ./try.nix
    ./upgrade.nix
    ./diff.nix
    ./private.nix
    ./unstable.nix
    ./graphical.nix
  ];

  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 10;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = config.nixos-central.hostname;
  networking.networkmanager.enable = true;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nixpkgs.config = (import ../../nixos-central-internal/lib/nixpkgs.nix { inherit inputs; }).config;

  # nix-shell -p / nix shell nixpkgs#... use the nixpkgs this system was built from.
  nix.channel.enable = false;
  nix.registry.nixpkgs.flake = inputs.nixpkgs;
  nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
}
