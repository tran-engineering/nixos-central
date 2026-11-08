# AppImages on every graphical desktop: a downloaded .AppImage starts when run
# (`./App.AppImage` or a double-click after `chmod +x`). binfmt_misc hands both
# AppImage types to appimage-run, which provides the libraries they expect.
# Switched together with Flatpak (nixos-central.desktopApps.enable, flatpak.nix).
{ config, lib, ... }:
{
  config = lib.mkIf config.nixos-central.desktopApps.enable {
    programs.appimage = {
      enable = true;
      binfmt = true;
    };
  };
}
