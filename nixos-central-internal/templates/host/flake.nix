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
        keyboardLayout = "@KEYBOARD_LAYOUT@"; # one of: @KEYBOARD_LAYOUTS@
        timeZone = "@TIME_ZONE@"; # e.g. Europe/Zurich; list: timedatectl list-timezones
        stateVersion = "@STATE_VERSION@"; # release this machine was installed with; do not change
        nvidia = @NVIDIA@; # NVIDIA GPU, or null; add channel = "unstable"; for a newer driver (README, "NVIDIA graphics")
        modules = [ ./hardware-configuration.nix ];
      };
    };
}
