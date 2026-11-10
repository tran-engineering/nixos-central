# Shared base configuration for every machine.
{ config, inputs, ... }:
{
  imports = [
    ./appimage.nix
    ./auto-upgrade.nix
    ./command.nix
    ./docker.nix
    ./envfs.nix
    ./flatpak.nix
    ./fwupd.nix
    ./gc.nix
    ./nvidia.nix
    ./reboot-notify.nix
    ./tailscale.nix
    ./try.nix
    ./u2f.nix
    ./upgrade.nix
    ./diff.nix
    ./private.nix
    ./unstable.nix
    ./graphical.nix
    ./keyboard.nix
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
