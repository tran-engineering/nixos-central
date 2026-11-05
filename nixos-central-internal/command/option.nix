# The `nixos-central.commands` option, declared by both module systems
# (modules/base/command.nix, modules/home/command.nix): the subcommands of the
# `nixos-central` command, from which its help, menu and completions are built.
{ lib }:
let
  inherit (lib) mkOption types;
in
mkOption {
  type = types.attrsOf (
    types.submodule {
      options = {
        package = mkOption {
          type = types.package;
          description = "Package whose main program runs the subcommand.";
        };
        description = mkOption {
          type = types.str;
          description = "One line for the help and the menu.";
        };
        usage = mkOption {
          type = types.str;
          default = "";
          description = "Arguments shown in the help after the subcommand's name.";
        };
        order = mkOption {
          type = types.int;
          default = 100;
          description = "Position in the help and the menu (lower first, then by name).";
        };
        chooser = mkOption {
          type = types.bool;
          default = true;
          description = "Whether the menu of `nixos-central` without arguments offers it (it runs without arguments).";
        };
        completions = mkOption {
          type = types.attrsOf (types.listOf types.str);
          default = { };
          example = {
            "" = [
              "setup"
              "remove"
            ];
            setup = [ "--profile" ];
          };
          description = ''
            Words the shells complete: under `""` directly after the subcommand,
            under any other word once that word was typed after the subcommand.
            Words already typed are not offered again.
          '';
        };
      };
    }
  );
  default = { };
  internal = true;
  description = "Subcommands of the nixos-central command.";
}
