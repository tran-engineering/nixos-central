# Shared home module: git with workflow defaults. Opt in from a profile with
#   imports = [ ../../modules/home/git.nix ];
# Each setting is a separate lib.mkDefault, so a profile overrides one by
# setting the same option (a mkDefault on the whole settings attrset would be
# dropped entirely as soon as the profile sets any key, e.g. user.name).
# Identity (name, email) belongs in the profile.
{ lib, ... }:
{
  programs.git = {
    enable = true;
    lfs.enable = lib.mkDefault true;
    settings = {
      push.autoSetupRemote = lib.mkDefault true;
      pull.rebase = lib.mkDefault true;
      rebase.autoStash = lib.mkDefault true;
    };
  };
}
