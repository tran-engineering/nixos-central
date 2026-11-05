# Subcommands of the nixos-central command contributed by home modules
# (status, and upgrade/diff/private on standalone homes). On NixOS the system
# builds the command, including these (modules/base/command.nix); a standalone
# home installs its own.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.nixos-central.commands = import ../../nixos-central-internal/command/option.nix {
    inherit lib;
  };

  config = lib.mkIf config.nixos-central.updateNotice.standalone {
    home.packages = [
      (pkgs.callPackage ../../nixos-central-internal/command { inherit (config.nixos-central) commands; })
    ];
  };
}
