# This user's environment (standalone home-manager, no NixOS). Everything
# except the facts below comes from the central repository and is updated
# automatically. Personal settings belong in a private overlay, not here:
# nixos-central private setup [<flake-url>] [--profile NAME]
#
# After editing, apply with:  home-manager switch --flake ~/.config/home-manager
{
  inputs.central.url = "@CENTRAL@";

  outputs =
    { central, ... }:
    {
      homeConfigurations."@USER@" = central.lib.mkHome {
        user = "@USER@";
        homeDirectory = "@HOME@";
        system = "@SYSTEM@";
        stateVersion = "@STATE_VERSION@"; # release this home was installed with; do not change
        nvidia = @NVIDIA@; # host's NVIDIA driver { version; sha256; }, or null; must match the installed driver
      };
    };
}
