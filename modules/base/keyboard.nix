# The machine's default keyboard layout (fact set by the installer): the
# console keymap for the TTYs and the disk passphrase prompt in the initrd, and
# the XKB layout of the graphical session. Graphical sessions take the XKB
# settings from /etc/X11/xorg.conf.d/00-keyboard.conf, which NixOS writes from
# them (GDM, GNOME, KDE and niri all default to it).
{ config, lib, ... }:
let
  layout = (import ../../nixos-central-internal/lib/keyboard-layouts.nix).${config.nixos-central.keyboardLayout};
in
{
  console.keyMap = layout.consoleKeyMap;
  services.xserver.xkb.layout = layout.xkbLayout;
  services.xserver.xkb.variant = layout.xkbVariant;
}
