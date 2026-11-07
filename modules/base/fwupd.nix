# Firmware updates (UEFI, SSDs, docks, …) from the LVFS. The update list is
# refreshed daily (fwupd-refresh.timer); installing stays manual, because
# firmware updates often need a reboot and can't be rolled back like a
# generation. KDE shows them in Discover; elsewhere use fwupdmgr (README,
# "Firmware updates").
{
  services.fwupd.enable = true;
}
