# Machine facts, set by lib.mkHost from the machine's /etc/nixos/flake.nix.
{ lib, ... }:
let
  desktopNames = import ../lib/desktop-names.nix;
in
{
  options.nixos-central = {
    hostname = lib.mkOption {
      type = lib.types.strMatching "[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?";
      description = "Hostname of the machine.";
    };

    user = lib.mkOption {
      type = lib.types.strMatching "[a-z][a-z0-9_-]{0,31}";
      description = "Login name of the machine's primary user.";
    };

    desktop = lib.mkOption {
      type = lib.types.enum desktopNames;
      description = "Desktop environment, one of the files in modules/desktops.";
    };

    disk = lib.mkOption {
      type = lib.types.str;
      example = "/dev/disk/by-id/nvme-Samsung_SSD_980_1TB_S64ANS0T123456";
      description = "Disk the system was installed on.";
    };

    repo = lib.mkOption {
      type = lib.types.str;
      default = "github:tran-engineering/nixos-central";
      description = "Flake reference of the central repository, used by nixos-central-try.";
    };
  };
}
