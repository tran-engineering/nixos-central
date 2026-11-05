# The nixos-central command of a machine: the subcommands of the NixOS modules
# (upgrade, try, diff, private) and of the primary user's home (status), in one
# command on the system's PATH. The home doesn't install its own
# (modules/home/command.nix), which would shadow this one.
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

  config.environment.systemPackages = [
    (pkgs.callPackage ../../nixos-central-internal/command {
      commands =
        config.home-manager.users.${config.nixos-central.user}.nixos-central.commands
        // config.nixos-central.commands;
    })
  ];
}
