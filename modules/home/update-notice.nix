# Part of every profile (NixOS: modules/user.nix, standalone: lib.mkHome).
# New interactive shells print a short notice when the last successful update is
# older than nixos-central.updateNotice.days. Successful updates are recorded by
# modules/base/auto-upgrade.nix and upgrade.nix (NixOS) and standalone.nix; a
# newer generation counts too (manual rebuilds, fresh installs).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixos-central.updateNotice;

  notice = pkgs.writeShellApplication {
    name = "nixos-central-update-notice";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    # NIXOS_CENTRAL_NOTICE_* are only set by tests.
    text = ''
      days=''${NIXOS_CENTRAL_NOTICE_DAYS:-${toString cfg.days}}
      now=''${NIXOS_CENTRAL_NOTICE_NOW:-$(date +%s)}
      stamp=''${NIXOS_CENTRAL_NOTICE_STAMP:-${lib.escapeShellArg cfg.stamp}}
    ''
    + (
      if cfg.standalone then
        ''
          lock=''${NIXOS_CENTRAL_NOTICE_LOCK:-$HOME/.config/home-manager/flake.lock}
          profile=''${NIXOS_CENTRAL_NOTICE_PROFILE:-''${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/home-manager}
          [ -e "$profile" ] || profile=/nix/var/nix/profiles/per-user/$USER/home-manager
          running=$profile
          what="home configuration"
          hint="Check the daily update: systemctl --user status home-manager-auto-upgrade"
        ''
      else
        ''
          lock=''${NIXOS_CENTRAL_NOTICE_LOCK:-/etc/nixos/flake.lock}
          profile=''${NIXOS_CENTRAL_NOTICE_PROFILE:-/nix/var/nix/profiles/system}
          running=''${NIXOS_CENTRAL_NOTICE_RUNNING:-/run/current-system}
          booted=''${NIXOS_CENTRAL_NOTICE_BOOTED:-/run/booted-system}
          what="running system"
          hint="Run nixos-central-upgrade to update now (log of the daily update: journalctl -u nixos-upgrade)."
          # Staged for the next boot, as in modules/base/reboot-notify.nix.
          if [ -e "$profile" ]; then
            staged=$(readlink -f "$profile")
            if [ "$staged" != "$(readlink -f "$booted")" ] && [ "$staged" != "$(readlink -f "$running")" ]; then
              hint="An update is installed; reboot to use it."
            fi
          fi
        ''
    )
    + ''
      [ "$days" -gt 0 ] || exit 0

      # Creation time of a generation link (not of the store path it points to).
      mtime() { stat -c %Y "$1" 2>/dev/null; }

      ago() {
        local d=$(( (now - $1) / 86400 ))
        if [ "$d" -le 0 ]; then echo "today"
        elif [ "$d" -eq 1 ]; then echo "1 day ago"
        else echo "$d days ago"
        fi
      }

      last=0
      if [ -e "$stamp" ]; then last=$(mtime "$stamp" || echo 0); fi

      # Newest generation: the link the profile points to (relative or absolute).
      if [ -L "$profile" ]; then
        newest=$(readlink "$profile")
        case "$newest" in /*) ;; *) newest=$(dirname "$profile")/$newest ;; esac
        t=$(mtime "$newest" || echo 0)
        [ "$t" -le "$last" ] || last=$t
      fi

      [ "$last" -gt 0 ] || exit 0
      [ $(( now - last )) -gt $(( days * 86400 )) ] || exit 0

      details=()
      target=$(readlink -f "$running" || true)
      shopt -s nullglob
      for link in "$profile"-*-link; do
        if [ "$(readlink -f "$link")" = "$target" ]; then
          details+=("$what installed $(ago "$(mtime "$link")")")
          break
        fi
      done
      central=$(jq -r '.nodes.central.locked.lastModified // empty' "$lock" 2>/dev/null || true)
      if [ -n "$central" ]; then
        details+=("central revision committed $(ago "$central")")
      fi

      joined=""
      for d in "''${details[@]}"; do joined="''${joined:+$joined, }$d"; done
      echo "nixos-central: last successful update $(ago "$last")''${joined:+ ($joined)}."
      echo "$hint"
    '';
  };

  call = "${lib.getExe notice} 2>/dev/null";
in
{
  options.nixos-central.updateNotice = {
    days = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 7;
      description = "Print a notice in new terminals when the last successful update is older than this many days. 0 turns it off.";
    };

    standalone = lib.mkOption {
      type = lib.types.bool;
      default = false;
      internal = true;
      description = "Whether this is a standalone home (set by standalone.nix).";
    };

    stamp = lib.mkOption {
      type = lib.types.str;
      internal = true;
      readOnly = true;
      default =
        if cfg.standalone then "${config.xdg.stateHome}/nixos-central/last-update" else "/var/lib/nixos-central/last-update";
      defaultText = lib.literalMD "`/var/lib/nixos-central/last-update`, or under `xdg.stateHome` for standalone homes";
      description = "File whose modification time is the last successful update.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      internal = true;
      readOnly = true;
      default = notice;
      description = "The notice script (used by the tests).";
    };
  };

  # Only interactive shells read these.
  config = lib.mkIf (cfg.days > 0) {
    programs.bash.initExtra = lib.mkAfter "${call} || true";
    programs.zsh.initContent = lib.mkAfter "${call} || true";
    programs.fish.interactiveShellInit = lib.mkAfter call;
  };
}
