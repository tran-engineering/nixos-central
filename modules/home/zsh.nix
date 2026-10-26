# Shared home module: zsh with completion, suggestions from history and syntax
# highlighting. Opt in from a profile with
#   imports = [ ../../modules/home/zsh.nix ];
# To make zsh the login shell, also set nixos-central.shell = "zsh".
{ lib, ... }:
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    history = {
      size = lib.mkDefault 50000;
      save = lib.mkDefault 50000;
      share = lib.mkDefault true; # across open shells
      ignoreAllDups = lib.mkDefault true;
      ignoreSpace = lib.mkDefault true; # commands starting with a space are not saved
    };
  };
}
