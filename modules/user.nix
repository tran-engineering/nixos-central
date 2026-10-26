# The machine's primary user: account and home-manager profile.
# The profile is users/<name> if the central repo has one, users/_default otherwise
# (see nixos-central-internal/lib/profiles.nix).
{ config, lib, pkgs, ... }:
let
  inherit (config.nixos-central) user;
  profile = ((import ../nixos-central-internal/lib/profiles.nix).resolve user).path;
  # Login shell selected by the profile (modules/home/shell.nix).
  shell = config.home-manager.users.${user}.nixos-central.shell;
in
{
  # NixOS needs the shell enabled system-wide to use it as a login shell
  # (/etc/shells, vendor completions). bash is the NixOS default; nothing to set.
  programs.fish.enable = lib.mkIf (shell == "fish") true;
  programs.zsh.enable = lib.mkIf (shell == "zsh") true;

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
    shell = lib.mkIf (shell != "bash") pkgs.${shell};
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "backup";
    sharedModules = [ ./home/shell.nix ];
    users.${user} = {
      imports = [ profile ];
      home.stateVersion = config.system.stateVersion;
    };
  };
}
