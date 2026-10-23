# Tell the desktop user once per staged generation that an update waits for a
# reboot. A generation activated with nixos-central-try is not "pending": it is
# compared against both the booted and the running system.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  notify = pkgs.writeShellApplication {
    name = "nixos-central-reboot-notify";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.libnotify
    ];
    text = ''
      [ -e /nix/var/nix/profiles/system ] || exit 0
      staged=$(readlink -f /nix/var/nix/profiles/system)
      booted=$(readlink -f /run/booted-system)
      current=$(readlink -f /run/current-system)
      [ "$staged" != "$booted" ] && [ "$staged" != "$current" ] || exit 0

      marker="''${XDG_RUNTIME_DIR:?}/nixos-central-reboot-notified"
      [ "$(cat "$marker" 2>/dev/null)" != "$staged" ] || exit 0

      notify-send --app-name="nixos-central" --icon=system-reboot \
        "Update ready – reboot when convenient" \
        "A system update has been installed and will be used after the next reboot."
      printf '%s\n' "$staged" > "$marker"
      echo "notified about $staged"
    '';
  };
in
{
  config = lib.mkIf (config.nixos-central.desktop != "none") {
    systemd.user.services.nixos-central-reboot-notify = {
      description = "Notify about a staged system update";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe notify;
      };
    };

    systemd.user.timers.nixos-central-reboot-notify = {
      description = "Periodically check for a staged system update";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      timerConfig = {
        OnActiveSec = "1min";
        OnUnitActiveSec = "30min";
      };
    };
  };
}
