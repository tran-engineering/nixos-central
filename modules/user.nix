# The machine's primary user: account and home-manager configuration.
# Every primary user gets the base configuration (home/base.nix). A private
# overlay adds its profile on top (nixos-central-internal/lib/default.nix),
# selected by the recorded profile (nixos-central.profile), else the user's name.
{ config, inputs, lib, pkgs, ... }:
let
  inherit (config.nixos-central) user;
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
    sharedModules = [
      ./home/base.nix
      ./home/shell.nix
      ./home/private.nix
      ./home/command.nix
      ./home/update-notice.nix
      ./home/gc.nix
      inputs.plasma-manager.homeModules.plasma-manager
    ];
    users.${user}.home.stateVersion = config.system.stateVersion;
  };
}
