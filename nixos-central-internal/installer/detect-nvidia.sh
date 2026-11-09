#!/usr/bin/env bash
# Prints the value of the machine flake's nvidia fact for this machine:
#   null                                                    no NVIDIA GPU
#   { }                                                     NVIDIA GPU, no PRIME
#   { intelBusId = "..."; nvidiaBusId = "..."; }            hybrid laptop
#
#   detect-nvidia.sh [sysfs-root]
#
# Run by the installer (lib.nvidiaDetect); tested against fake sysfs trees by
# the nvidia-detect check. Only a machine with a system battery counts as a
# hybrid laptop: a desktop with an enabled integrated GPU usually has its
# displays on the NVIDIA GPU, which offload would get wrong.
set -euo pipefail

root=${1:-/sys}

# 0000:0a:00.0 -> PCI:10@0:0:0. Sysfs is hexadecimal, the bus IDs are decimal.
bus_id() {
  local domain bus device function rest
  IFS=:. read -r domain bus device function rest <<<"$1"
  printf 'PCI:%d@%d:%d:%d' "$((16#$bus))" "$((16#$domain))" "$((16#$device))" "$((16#$function))"
}

# Peripherals such as wireless mice report a battery with scope "Device".
has_system_battery() {
  local supply scope
  for supply in "$root"/class/power_supply/*; do
    [ "$(cat "$supply/type" 2>/dev/null)" = Battery ] || continue
    scope=$(cat "$supply/scope" 2>/dev/null || true)
    [ "$scope" = Device ] || return 0
  done
  return 1
}

nvidia="" intel="" amd=""
for device in "$root"/bus/pci/devices/*; do
  [ -r "$device/class" ] || continue
  case "$(cat "$device/class")" in 0x03*) ;; *) continue ;; esac # display controllers
  address=${device##*/}
  case "$(cat "$device/vendor")" in
    0x10de) nvidia=${nvidia:-$address} ;;
    0x8086) intel=${intel:-$address} ;;
    0x1002) amd=${amd:-$address} ;;
  esac
done

if [ -z "$nvidia" ]; then
  echo null
elif ! has_system_battery; then
  echo "{ }"
elif [ -n "$intel" ]; then
  echo "{ intelBusId = \"$(bus_id "$intel")\"; nvidiaBusId = \"$(bus_id "$nvidia")\"; }"
elif [ -n "$amd" ]; then
  echo "{ amdgpuBusId = \"$(bus_id "$amd")\"; nvidiaBusId = \"$(bus_id "$nvidia")\"; }"
else
  echo "{ }"
fi
