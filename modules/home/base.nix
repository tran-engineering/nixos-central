# Base home configuration of every user: the primary user of each NixOS machine
# (modules/user.nix) and every standalone home (lib.mkHome), with or without a
# private overlay. Its settings are defaults; overlay profiles override them by
# setting the same option, without mkForce. Not a shared module for profiles to
# pick (see the `internal` list in nixos-central-internal/lib/overlay.nix).
{ lib, pkgs, ... }:
{
  programs.bash.enable = lib.mkDefault true;

  programs.git = {
    enable = lib.mkDefault true;
    settings.init.defaultBranch = lib.mkDefault "main";
  };

  programs.firefox.enable = lib.mkDefault true;

  home.packages = with pkgs; [
    vim
    htop
    wget
    unzip
  ];

  home.sessionVariables.EDITOR = lib.mkDefault "vim";
}
