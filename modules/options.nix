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

    keyboardLayout = lib.mkOption {
      type = lib.types.enum (builtins.attrNames (import ../nixos-central-internal/lib/keyboard-layouts.nix));
      default = "us";
      description = "Default keyboard layout of the machine, for the console and the graphical session. One of the names in nixos-central-internal/lib/keyboard-layouts.nix (us, de, sg = Swiss German, sf = Swiss French).";
    };

    profile = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "[A-Za-z0-9._-]+");
      default = null;
      description = "Profile of the private overlay (homeModules.<profile>) used in place of the primary user's name. Without an overlay it has no effect (warning). The account keeps the user's name. null: the user's name.";
    };

    nvidia = lib.mkOption {
      type =
        let
          busId =
            description:
            lib.mkOption {
              type = lib.types.nullOr (lib.types.strMatching "PCI:[0-9]{1,3}@[0-9]{1,10}:[0-9]{1,2}:[0-9]");
              default = null;
              example = "PCI:1@0:0:0";
              inherit description;
            };
        in
        lib.types.nullOr (
          lib.types.submodule {
            options = {
              channel = lib.mkOption {
                type = lib.types.enum [
                  "stable"
                  "unstable"
                ];
                default = "stable";
                description = "Where the driver comes from: the production driver of the system's nixpkgs, or the newest driver of the nixos-unstable input, built locally against the machine's kernel.";
              };
              nvidiaBusId = busId "Bus ID of the NVIDIA GPU, in decimal, on a hybrid laptop. Needs intelBusId or amdgpuBusId.";
              intelBusId = busId "Bus ID of the integrated Intel GPU, in decimal, on a hybrid laptop.";
              amdgpuBusId = busId "Bus ID of the integrated AMD GPU, in decimal, on a hybrid laptop.";
            };
          }
        );
      default = null;
      example = {
        intelBusId = "PCI:0@0:2:0";
        nvidiaBusId = "PCI:1@0:0:0";
      };
      description = "The machine's NVIDIA GPU (modules/base/nvidia.nix). null: no NVIDIA driver. Bus IDs select PRIME offload.";
    };

    private.enable = lib.mkEnableOption "the private overlay of the machine flake (set by mkHost)";

    repo = lib.mkOption {
      type = lib.types.str;
      default = "git+https://github.com/tran-engineering/nixos-central";
      description = "Flake reference of the central repository, used by nixos-central try.";
    };
  };
}
