# Home-manager module for standalone homes (lib.mkHome) on Linux distributions
# other than NixOS. Facts (user, home directory, NVIDIA driver) are set by mkHome.
{ config, lib, pkgs, ... }:
let
  # Inputs nixos-central upgrade updates (and nothing else).
  updateInputs = [ "central" ] ++ lib.optional config.nixos-central.private.enable "private";
  # Rewrites the recorded NVIDIA driver when the host's loaded driver changed.
  nvidia-pin = pkgs.callPackage ../../nixos-central-internal/home-upgrade/nvidia-pin.nix { };
in
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

  # Subcommands of the home's nixos-central command (modules/home/command.nix).
  nixos-central.commands = {
    # The only way the home is updated; nothing upgrades it automatically.
    upgrade = (import ../../nixos-central-internal/command/subcommands.nix).upgrade // {
      package = pkgs.callPackage ../../nixos-central-internal/home-upgrade {
        inherit updateInputs nvidia-pin;
        # Where home-only.sh writes the home's flake.
        flakeDir = "${config.xdg.configHome}/home-manager";
        # Keep files home-manager would replace as <name>.backup.
        switchFlags = [
          "-b"
          "backup"
        ];
        # Seen by the update notice (update-notice.nix).
        inherit (config.nixos-central.updateNotice) stamp;
        nix = config.nix.package;
        home-manager = config.programs.home-manager.package;
      };
    };
    # What the last update changed.
    diff = (import ../../nixos-central-internal/command/subcommands.nix).diff // {
      package = pkgs.callPackage ../../nixos-central-internal/diff { mode = "home"; };
    };
    # Shows, adds or removes the private overlay (README, "Private overlay").
    private = (import ../../nixos-central-internal/command/subcommands.nix).private // {
      package = pkgs.callPackage ../../nixos-central-internal/private { };
    };
  };

  nixos-central.updateNotice.standalone = true;
}
