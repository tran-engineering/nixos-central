# This machine's configuration. Everything except the facts below comes from
# the central repository and is updated automatically.
#
# After editing, apply with:  sudo nixos-rebuild switch --flake /etc/nixos
{
  inputs.central.url = "@CENTRAL@";

  outputs =
    { central, ... }:
    {
      nixosConfigurations."@HOSTNAME@" = central.lib.mkHost {
        hostname = "@HOSTNAME@";
        user = "@USER@";
        desktop = "@DESKTOP@"; # one of: @DESKTOPS@
        disk = "@DISK@";
        stateVersion = "@STATE_VERSION@"; # release this machine was installed with; do not change
        modules = [ ./hardware-configuration.nix ];
      };
    };
}
