# The machine's primary user: account and home-manager profile.
# The profile is users/<name> if the central repo has one, users/_default otherwise.
# Checked on every build, so a profile merged later is picked up by the next update.
{ config, ... }:
let
  inherit (config.nixos-central) user;
  personal = ../users + "/${user}";
  profile = if builtins.pathExists personal then personal else ../users/_default;
in
{
  users.mutableUsers = false;
  users.users.root.hashedPassword = "!"; # no root login; admin via sudo

  users.users.${user} = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    # Written by the installer; never part of the Nix store.
    hashedPasswordFile = "/etc/secrets/${user}.hash";
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "backup";
    users.${user} = {
      imports = [ profile ];
      home.stateVersion = config.system.stateVersion;
    };
  };
}
