# Machine facts, set by lib.mkHost from the machine's /etc/nixos/flake.nix.
{ lib, ... }:
let
  desktopNames = import ../nixos-central-internal/lib/desktop-names.nix;
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

    private.enable = lib.mkEnableOption "the private overlay of the machine flake (set by mkHost)";

    repo = lib.mkOption {
      type = lib.types.str;
      default = "git+https://github.com/tran-engineering/nixos-central";
      description = "Flake reference of the central repository, used by nixos-central-try.";
    };
  };
}
