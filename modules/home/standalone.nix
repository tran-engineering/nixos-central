# Home-manager module for standalone homes (lib.mkHome) on Linux distributions
# other than NixOS. Facts (user, home directory, NVIDIA driver) are set by mkHome.
{ config, pkgs, ... }:
{
  # Integrates with the host: XDG paths, and GPU drivers for Nix programs after
  # a one-time `sudo non-nixos-gpu-setup` (offered by home-only.sh).
  targets.genericLinux.enable = true;

  # NixOS machines get fonts from the system; here the profile's fonts must be
  # found per user.
  fonts.fontconfig.enable = true;

  # Flakes for the user's nix commands (the official installer leaves them off).
  nix.package = pkgs.nix;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # home-manager CLI for manual switches and rollbacks.
  programs.home-manager.enable = true;

  # Adds or removes the private overlay (README, "Private overlay").
  home.packages = [ (pkgs.callPackage ../../nixos-central-internal/private { }) ];

  # Daily: bump the `central` input (and the private overlay, if any) in
  # ~/.config/home-manager and switch to it.
  # Without preSwitchCommands the timer would rebuild the same locked revision
  # forever (the default is empty since home-manager 26.05).
  services.home-manager.autoUpgrade = {
    enable = true;
    frequency = "daily";
    useFlake = true;
    preSwitchCommands = [
      (if config.nixos-central.private.enable then "nix flake update central private" else "nix flake update central")
    ];
    flags = [
      "-b"
      "backup"
    ];
  };
}
