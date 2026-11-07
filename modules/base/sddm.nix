# Catppuccin (Mocha) SDDM theme on every machine that uses SDDM (kde,
# niri-noctalia). A private overlay can still pick another theme by setting
# services.displayManager.sddm.theme normally.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  flavor = "mocha";
  accent = "mauve";
  theme = pkgs.catppuccin-sddm.override { inherit flavor accent; };
in
{
  config = lib.mkIf config.services.displayManager.sddm.enable {
    # Beats Plasma's mkDefault "breeze" (1000) but loses to a plain setting (100).
    services.displayManager.sddm.theme = lib.mkOverride 900 "catppuccin-${flavor}-${accent}";
    # The greeter loads the theme's SVG icons through qtsvg.
    services.displayManager.sddm.extraPackages = [ pkgs.kdePackages.qtsvg ];
    environment.systemPackages = [ theme ];
    # The theme's font; Plasma installs it already, niri does not.
    fonts.packages = [ pkgs.noto-fonts ];
  };
}
