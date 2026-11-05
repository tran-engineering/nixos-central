# Keyboard layouts offered by the installer (fact: keyboardLayout), with how
# each one reaches the console (kbd keymap for the TTYs and the disk passphrase
# prompt) and the graphical session (xkeyboard-config layout and variant; NixOS
# writes them to /etc/X11/xorg.conf.d/00-keyboard.conf, where display managers
# and Wayland sessions pick them up via org.freedesktop.locale1). "sg"/"sf" keep
# the historical Swiss keymap names; kbd renamed sf-latin1 to fr_CH-latin1.
{
  us = {
    consoleKeyMap = "us";
    xkbLayout = "us";
    xkbVariant = "";
  };
  de = {
    consoleKeyMap = "de-latin1";
    xkbLayout = "de";
    xkbVariant = "";
  };
  sg = {
    consoleKeyMap = "sg-latin1";
    xkbLayout = "ch";
    xkbVariant = "";
  };
  sf = {
    consoleKeyMap = "fr_CH-latin1";
    xkbLayout = "ch";
    xkbVariant = "fr";
  };
}
