# NVIDIA GPUs (README, "NVIDIA graphics"), for machines whose flake sets the
# nvidia fact: always the open kernel modules with NVIDIA's proprietary
# userspace. Bus IDs in the fact select PRIME offload for hybrid laptops.
{
  config,
  inputs,
  lib,
  ...
}:
let
  cfg = config.nixos-central.nvidia;

  # All null without the fact, so the conditions below can be evaluated either way.
  fact = {
    channel = "stable";
    nvidiaBusId = null;
    intelBusId = null;
    amdgpuBusId = null;
  }
  // (if cfg == null then { } else cfg);
  integratedBusIds = lib.filter (id: id != null) [
    fact.intelBusId
    fact.amdgpuBusId
  ];
  hybrid = fact.nvidiaBusId != null || integratedBusIds != [ ];

  # The driver's definition from unstable, with the kernel and libraries of the
  # system's nixpkgs: kernel modules must be built against the kernel that loads
  # them, and pkgs.unstable's kernel is a different build even at the same version.
  unstableDrivers = config.boot.kernelPackages.callPackage "${inputs.nixpkgs-unstable}/pkgs/os-specific/linux/nvidia-x11/default.nix" { };
in
{
  config = lib.mkIf (cfg != null) (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = !hybrid || (fact.nvidiaBusId != null && builtins.length integratedBusIds == 1);
            message = "nixos-central.nvidia: for PRIME offload set nvidiaBusId and exactly one of intelBusId and amdgpuBusId; without PRIME set none of them.";
          }
        ];

        services.xserver.videoDrivers = [ "nvidia" ];
        hardware.nvidia.open = true;
        hardware.nvidia.powerManagement.enable = true;

        # Docker is on every machine (docker.nix); this also enables its CDI
        # feature: docker run --device nvidia.com/gpu=all ...
        hardware.nvidia-container-toolkit.enable = true;
      }

      (lib.mkIf (fact.channel == "unstable") {
        hardware.nvidia.package = unstableDrivers.latest;
      })

      (lib.mkIf hybrid {
        hardware.nvidia.prime = {
          offload.enable = true;
          offload.enableOffloadCmd = true; # nvidia-offload <program>
        }
        // lib.filterAttrs (_: id: id != null) {
          inherit (fact) nvidiaBusId intelBusId amdgpuBusId;
        };
        # The NVIDIA GPU powers down while no program uses it.
        hardware.nvidia.powerManagement.finegrained = true;
      })
    ]
  );
}
