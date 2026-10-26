# Shared home module: the Ghostty terminal. Opt in from a profile with
#   imports = [ ../../modules/home/ghostty.nix ];
# Each setting is a default; a profile overrides one by setting the same
# option, e.g. programs.ghostty.settings.font-size = 12. Font and theme belong
# in the profile. Ghostty ships Nerd Font icons built in.
{ lib, ... }:
{
  programs.ghostty = {
    enable = true;
    settings = lib.mapAttrs (_: lib.mkDefault) {
      font-size = 14;

      window-padding-x = 12;
      window-padding-y = 12;

      cursor-style = "block";
      cursor-style-blink = true;

      scrollback-limit = 10000;

      mouse-hide-while-typing = true;
      copy-on-select = true;
      confirm-close-surface = false;

      # No popups for clipboard copies and config reloads.
      app-notifications = "no-clipboard-copy,no-config-reload";

      # Dim unfocused splits.
      unfocused-split-opacity = 0.7;

      gtk-single-instance = true;

      shell-integration = "detect";
      shell-integration-features = "cursor,sudo,title,no-cursor";

      keybind = [
        "ctrl+shift+n=new_window"
        "ctrl+t=new_tab"
        "ctrl+plus=increase_font_size:1"
        "ctrl+minus=decrease_font_size:1"
        "ctrl+zero=reset_font_size"
        "shift+enter=text:\\n"
      ];
    };
  };
}
