# Shared home module: the foot terminal (Wayland). Opt in from a profile with
#   imports = [ ../../modules/home/foot.nix ];
# Each setting is a default; a profile overrides one by setting the same
# option, e.g. programs.foot.settings.main.font = "...". Font and theme belong
# in the profile.
{ lib, pkgs, ... }:
{
  programs.foot = {
    enable = true;
    settings = {
      main.initial-window-size-chars = lib.mkDefault "128x40";
      scrollback.lines = lib.mkDefault 10000;
      mouse.hide-when-typing = lib.mkDefault "yes";
    };
  };

  # Icons (e.g. of the fish prompt); fontconfig falls back to it whatever the
  # main font is.
  home.packages = [ pkgs.nerd-fonts.symbols-only ];
  fonts.fontconfig.enable = true;
}
