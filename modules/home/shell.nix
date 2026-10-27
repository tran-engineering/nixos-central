# Part of every profile (NixOS: modules/user.nix, standalone: lib.mkHome).
# A profile selects the login shell with
#   nixos-central.shell = "fish";
# NixOS machines make it the primary user's login shell; standalone homes can't
# change it without root, so home-only.sh prints the chsh command instead.
{ config, lib, ... }:
{
  options.nixos-central.shell = lib.mkOption {
    type = lib.types.enum [
      "bash"
      "fish"
      "zsh"
    ];
    default = "bash";
    description = "Login shell of the user. The shared fish and zsh modules configure the shells further.";
  };

  # The selected shell works even without its shared module.
  config.programs = {
    bash.enable = lib.mkIf (config.nixos-central.shell == "bash") true;
    fish.enable = lib.mkIf (config.nixos-central.shell == "fish") true;
    zsh.enable = lib.mkIf (config.nixos-central.shell == "zsh") true;
  };
}
