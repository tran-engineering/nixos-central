# GNOME on Wayland (login screen: GDM, modules/base/graphical.nix).
{ config, lib, pkgs, ... }:
let
  dashToDock = pkgs.gnomeExtensions.dash-to-dock;
in
{
  config = lib.mkIf (config.nixos-central.desktop == "gnome") {
    services.desktopManager.gnome.enable = true;

    environment.systemPackages = [
      # Firmware updates (modules/base/fwupd.nix) in a window. GNOME Software
      # lists them too (nixpkgs installs it with Flatpak, modules/base/flatpak.nix);
      # kept because users know this app.
      pkgs.gnome-firmware
      dashToDock
    ];

    # A dock on the left, always visible and full height (as Ubuntu's), via
    # Dash to Dock. System-wide defaults only: a user's own settings win, so
    # the dock can be moved, hidden or the extension turned off in Extensions.
    # A user who already changed the list of enabled extensions keeps theirs.
    programs.dconf.profiles.user.databases = [
      {
        settings = {
          "org/gnome/shell".enabled-extensions = [ dashToDock.extensionUuid ];
          "org/gnome/shell/extensions/dash-to-dock" = {
            dock-position = "LEFT";
            dock-fixed = true;
            extend-height = true;
          };
        };
      }
    ];
  };
}
