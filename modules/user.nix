# The machine's primary user: account and home-manager profile.
# The profile is users/<name> if the central repo has one, users/_default otherwise
# (see nixos-central-internal/lib/profiles.nix).
{ config, ... }:
let
  inherit (config.nixos-central) user;
  profile = ((import ../nixos-central-internal/lib/profiles.nix).resolve user).path;
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
