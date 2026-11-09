# What the activated system only uses after a reboot (part of modules/base/upgrade.nix).
if [ "$(readlink -f /run/booted-system/kernel)" != "$(readlink -f /run/current-system/kernel)" ]; then
  echo "The new kernel is used after the next reboot."
elif [ "$(readlink -f /run/booted-system/kernel-modules)" != "$(readlink -f /run/current-system/kernel-modules)" ]; then
  echo "The new drivers are used after the next reboot; programs using the GPU may fail until then."
fi
