# Disk layout for every nixos-central machine:
# GPT, 1 GiB EFI system partition, rest LUKS-encrypted ext4.
# Partitions are mounted by GPT label (disk-main-ESP, disk-main-luks), so the
# installed system does not depend on the device path.
{ config, ... }:
{
  disko.devices.disk.main = {
    type = "disk";
    device = config.nixos-central.disk;
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        luks = {
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            # Only read while formatting; the installer writes the passphrase
            # here on the live image's tmpfs and shreds it afterwards.
            passwordFile = "/tmp/nixos-central-luks.key";
            settings.allowDiscards = true;
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              mountOptions = [ "noatime" ];
            };
          };
        };
      };
    };
  };
}
