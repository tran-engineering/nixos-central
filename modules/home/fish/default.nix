# Shared home module: fish with the tide prompt and a few plugins. Opt in from
# a profile with
#   imports = [ ../../modules/home/fish ];
# To make fish the login shell, also set nixos-central.shell = "fish".
{ lib, pkgs, ... }:
{
  programs.fish = {
    enable = true;
    plugins = [
      {
        name = "tide";
        src = pkgs.fishPlugins.tide.src;
      }
      {
        name = "fzf-fish";
        src = pkgs.fishPlugins.fzf-fish.src;
      }
      {
        name = "z";
        src = pkgs.fishPlugins.z.src;
      }
      {
        name = "fish-cd-gitroot";
        src = pkgs.fetchFromGitHub {
          owner = "mollifier";
          repo = "fish-cd-gitroot";
          rev = "9b5c3732655ee99aefae04739242d6a1bab47be1";
          sha256 = "0nsk1v143ksph5m680hw11hpqizpzpkl5dfmwj5wi0hbklipbkm1";
        };
      }
    ];
  };

  # Tide installed as a plugin never runs its install hook, so its variables
  # come from here. In conf.d rather than fish_variables, so that file stays
  # writable by fish and `tide configure`.
  xdg.configFile."fish/conf.d/tide.fish".source = lib.mkDefault ./tide.fish;

  home.packages = with pkgs; [
    # Called by fzf-fish.
    fzf
    fd
    # Icons used by the tide prompt; fontconfig falls back to it whatever the
    # terminal's font is.
    nerd-fonts.symbols-only
  ];
  fonts.fontconfig.enable = true;
}
