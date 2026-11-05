# Home-manager module for standalone homes (lib.mkHome) on Linux distributions
# other than NixOS. Facts (user, home directory, NVIDIA driver) are set by mkHome.
{ config, lib, pkgs, ... }:
let
  # Inputs the daily upgrade and nixos-central upgrade update (and nothing else).
  updateInputs = [ "central" ] ++ lib.optional config.nixos-central.private.enable "private";
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
    # The daily upgrade below, right now.
    upgrade = (import ../../nixos-central-internal/command/subcommands.nix).upgrade // {
      package = pkgs.callPackage ../../nixos-central-internal/home-upgrade {
        inherit updateInputs;
        inherit (config.services.home-manager.autoUpgrade) flakeDir;
        switchFlags = config.services.home-manager.autoUpgrade.flags;
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

  # Daily: bump the `central` input (and the private overlay, if any) in
  # ~/.config/home-manager and switch to it.
  # Without preSwitchCommands the timer would rebuild the same locked revision
  # forever (the default is empty since home-manager 26.05).
  services.home-manager.autoUpgrade = {
    enable = true;
    frequency = "daily";
    useFlake = true;
    preSwitchCommands = [ "nix flake update ${lib.concatStringsSep " " updateInputs}" ];
    flags = [
      "-b"
      "backup"
    ];
  };

  # Record every successful run, also when nothing changed, for the update
  # notice (update-notice.nix). ExecStartPost only runs if the upgrade succeeded.
  systemd.user.services.home-manager-auto-upgrade.Service.ExecStartPost = toString (
    pkgs.writeShellScript "home-manager-auto-upgrade-record" ''
      stamp=${lib.escapeShellArg config.nixos-central.updateNotice.stamp}
      ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$stamp")"
      ${pkgs.coreutils}/bin/touch "$stamp"
    ''
  );
  nixos-central.updateNotice.standalone = true;
}
