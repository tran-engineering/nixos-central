# Weekly: delete system generations older than keepDays and collect garbage.
# Like `nix-collect-garbage --delete-older-than`, it keeps the generation that
# was active at the cutoff; unlike it, it never deletes the generation the
# machine is booted into or running (it can be older than staged ones when the
# machine isn't rebooted). The user's home generations are collected by
# modules/home/gc.nix.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixos-central.gc;

  gc = pkgs.writeShellApplication {
    name = "nixos-central-gc";
    runtimeInputs = [
      pkgs.coreutils
      config.nix.package
    ];
    text = ''
      profile=/nix/var/nix/profiles/system
      cutoff=$(( $(date +%s) - ${toString cfg.keepDays} * 86400 ))
      protected=(
        "$(readlink -f "$profile")"
        "$(readlink -f /run/booted-system)"
        "$(readlink -f /run/current-system)"
      )

      generations=()
      for link in "$profile"-*-link; do
        [ -L "$link" ] || continue
        n=''${link#"$profile"-}
        generations+=("''${n%-link}")
      done
      mapfile -t generations < <(printf '%s\n' "''${generations[@]}" | sort -n)

      # Newest first: generations newer than the cutoff stay, so does the newest
      # one older than it (active at the cutoff); older ones go unless protected.
      delete=()
      past_cutoff=false
      for (( i = ''${#generations[@]} - 1; i >= 0; i-- )); do
        n=''${generations[i]}
        link="$profile-$n-link"
        old=false
        [ "$(stat -c %Y "$link")" -ge "$cutoff" ] || old=true
        if ! $past_cutoff; then
          past_cutoff=$old
          continue
        fi
        $old || continue
        target=$(readlink -f "$link")
        for p in "''${protected[@]}"; do
          [ "$target" != "$p" ] || continue 2
        done
        delete+=("$n")
      done

      if [ ''${#delete[@]} -gt 0 ]; then
        echo "deleting system generations: ''${delete[*]}"
        nix-env -p "$profile" --delete-generations "''${delete[@]}"
      fi
      nix-collect-garbage

      # Drop deleted generations from the boot menu. The profile's generation
      # (possibly staged) stays the default.
      if [ ''${#delete[@]} -gt 0 ] && [ -x "$profile/bin/switch-to-configuration" ]; then
        "$profile/bin/switch-to-configuration" boot
      fi
    '';
  };
in
{
  options.nixos-central.gc = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to delete old system generations and collect garbage regularly.";
    };

    keepDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30;
      description = "System generations younger than this are kept, and the one active this many days ago.";
    };

    dates = lib.mkOption {
      type = lib.types.str;
      default = "weekly";
      description = "When to collect, in systemd.time(7) calendar format.";
    };
  };

  config = lib.mkMerge [
    {
      # Nix collects unreferenced paths itself while building when space runs
      # low (never generations), so updates don't fail between weekly runs.
      nix.settings.min-free = lib.mkDefault (2 * 1024 * 1024 * 1024);
      nix.settings.max-free = lib.mkDefault (10 * 1024 * 1024 * 1024);
    }

    (lib.mkIf cfg.enable {
      systemd.services.nixos-central-gc = {
        description = "Delete old system generations and collect garbage";
        restartIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe gc;
          Nice = 19;
          IOSchedulingClass = "idle";
        };
      };

      systemd.timers.nixos-central-gc = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.dates;
          Persistent = true;
          RandomizedDelaySec = "1h";
        };
      };
    })
  ];
}
