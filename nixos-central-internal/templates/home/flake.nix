# This user's environment (standalone home-manager, no NixOS). Everything
# except the facts below comes from the central repository and is updated
# automatically. Change the profile itself in the central repository, not here.
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
        profile = "@PROFILE@"; # one of: @PROFILES@
        stateVersion = "@STATE_VERSION@"; # release this home was installed with; do not change
        nvidia = @NVIDIA@; # host's NVIDIA driver { version; sha256; }, or null; must match the installed driver
      };
    };
}
