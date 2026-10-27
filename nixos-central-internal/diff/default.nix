# nixos-central-diff: the package changes of the last (or the staged) update,
# shown with dix like nh does. NixOS machines (modules/base/diff.nix) compare
# system generations, standalone homes (standalone.nix) home-manager ones.
{
  lib,
  writeShellApplication,
  coreutils,
  dix,
  # "system" or "home"
  mode,
}:
assert lib.assertOneOf "mode" mode [
  "system"
  "home"
];
writeShellApplication {
  name = "nixos-central-diff";
  runtimeInputs = [
    coreutils
    dix
  ];
  text = ''
    if [ $# -ne 0 ]; then
      echo "usage: nixos-central-diff" >&2
      echo "Shows the packages a pending update changes, or else those the last update changed." >&2
      exit 2
    fi

    ${
      if mode == "system" then
        ''
          profile=/nix/var/nix/profiles/system
        ''
      else
        ''
          profile=''${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/home-manager
          [ -L "$profile" ] || profile=/nix/var/nix/profiles/per-user/$USER/home-manager
        ''
    }
    none() {
      echo "No earlier generation to compare with."
      exit 0
    }
    [ -L "$profile" ] || none

    # <profile>-<n>-link -> n
    generation() {
      local n=''${1%-link}
      echo "''${n##*-}"
    }
    newest=$(generation "$(readlink "$profile")")

    ${lib.optionalString (mode == "system") ''
      # Staged by the daily upgrade (or a reboot ends a tried branch).
      staged=$(readlink -f "$profile")
      current=$(readlink -f /run/current-system)
      if [ "$staged" != "$current" ]; then
        echo "Pending on next reboot (generation $newest):"
        echo
        exec dix "$current" "$staged"
      fi
    ''}
    # The highest generation below the newest; GC may have removed some.
    previous=
    shopt -s nullglob
    for link in "$profile"-*-link; do
      n=$(generation "$link")
      if [ "$n" -lt "$newest" ] && { [ -z "$previous" ] || [ "$n" -gt "$previous" ]; }; then
        previous=$n
      fi
    done
    [ -n "$previous" ] || none

    echo "Changes from generation $previous to $newest:"
    echo
    exec dix "$profile-$previous-link" "$profile-$newest-link"
  '';
}
