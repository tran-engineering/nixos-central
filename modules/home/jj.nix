# Shared home module: jj (Jujutsu) and its TUI jjui, with workflow defaults.
# Opt in from a profile with
#   imports = [ ../../modules/home/jj.nix ];
# Each setting is a separate lib.mkDefault, so a profile overrides one by
# setting the same option. Identity (name, email) belongs in the profile.
{ lib, pkgs, ... }:
{
  home.packages = [ pkgs.jjui ];

  programs.jujutsu = {
    enable = true;
    settings = {
      remotes.origin = {
        # Track every bookmark pushed to origin, not just the ones fetched at
        # clone time.
        auto-track-bookmarks = lib.mkDefault "*";
        # Bookmarks created locally track origin too, like git's
        # push.autoSetupRemote.
        auto-track-created-bookmarks = lib.mkDefault "*";
      };

      # Refuse to push scratch commits.
      git.private-commits = lib.mkDefault ''description(glob:"wip:*") | description(glob:"private:*")'';

      # jj errors out instead of snapshotting new files above this size; the
      # 1MiB default is easy to trip over in repos with binaries.
      snapshot.max-new-file-size = lib.mkDefault "10MiB";
    };
  };
}
