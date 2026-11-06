# Edits that add or remove the private overlay (and a recorded profile) in a
# local flake. Shared by `nixos-central private` (prepended to its script) and
# the installer (sourced from the central repository), so both produce the same
# shape and `remove` undoes either. Callers define `die`.
#
#   flake_has_overlay           <flake>
#   flake_check_overlay_anchors <flake> <nixos|home> [profile]
#   flake_add_overlay           <flake> <nixos|home> <url> [profile]
#   flake_remove_overlay        <flake> <nixos|home>

PROFILE_COMMENT="# in the central repository or the private overlay"

flake_has_overlay() { grep -q '^ *inputs\.private\.url' "$1"; }

flake_sed_escape() { printf '%s' "$1" | sed 's/[\\|&]/\\&/g'; }

# Exactly one line matching the pattern, or explain and stop.
flake_require_anchor() {
  [ "$(grep -c "$2" "$1")" -eq 1 ] ||
    die "$1 does not have the expected shape (looking for: $3). Edit it by hand as described in the README, \"Private overlay\"."
}

# `inherit private;` goes into the mkHost/mkHome call, before this line.
flake_overlay_before() {
  if [ "$1" = home ]; then echo '^ *stateVersion = '; else echo '^ *modules = \['; fi
}

# Stops unless flake_add_overlay can edit the flake; changes nothing.
flake_check_overlay_anchors() {
  local flake=$1 mode=$2 profile=${3:-}
  flake_require_anchor "$flake" '^ *inputs\.central\.url = ' 'inputs.central.url = ...;'
  flake_require_anchor "$flake" '{ *central, *\.\.\. *}:' '{ central, ... }:'
  local before_text='modules = [ ... ];'
  [ "$mode" = nixos ] || before_text='stateVersion = "...";'
  flake_require_anchor "$flake" "$(flake_overlay_before "$mode")" "$before_text"
  [ -n "$profile" ] || return 0
  if [ "$mode" = nixos ] && ! grep -q '^ *profile = "[^"]*";' "$flake"; then
    flake_require_anchor "$flake" '^ *user = "[^"]*";' 'user = "...";'
  else
    flake_require_anchor "$flake" '^ *profile = "[^"]*";' 'profile = "...";'
  fi
}

# Checks every anchor before changing anything.
flake_add_overlay() {
  local flake=$1 mode=$2 url=$3 profile=${4:-}
  flake_check_overlay_anchors "$flake" "$mode" "$profile"
  local before has_profile=0 u p
  before=$(flake_overlay_before "$mode")
  if grep -q '^ *profile = "[^"]*";' "$flake"; then has_profile=1; fi
  u=$(flake_sed_escape "$url")
  sed -i \
    -e "s|^\( *\)inputs\.central\.url = \(.*\)$|&\n\1inputs.private.url = \"$u\";|" \
    -e 's|{ *central, *\.\.\. *}:|{ central, private, ... }:|' \
    -e "s|\($before\)|inherit private;\n&|" \
    "$flake"
  # Indent `inherit private;` like the line after it.
  sed -i -e '/^inherit private;$/{N;s/^inherit private;\n\( *\)\(.*\)$/\1inherit private;\n\1\2/}' "$flake"

  [ -n "$profile" ] || return 0
  p=$(flake_sed_escape "$profile")
  if [ "$has_profile" = 1 ]; then
    sed -i "s|^\( *profile = \)\"[^\"]*\";.*$|\1\"$p\"; $PROFILE_COMMENT|" "$flake"
  else
    # NixOS: the profile goes right after the user.
    sed -i "s|^\( *\)user = \"[^\"]*\";.*$|&\n\1profile = \"$p\"; $PROFILE_COMMENT|" "$flake"
  fi
}

# On NixOS the recorded profile goes too: without the overlay, the user's name
# selects the profile again. Standalone homes keep theirs (it is a fact of the
# home, from its template).
flake_remove_overlay() {
  local flake=$1 mode=$2
  local profile_expr='/^ *profile = "[^"]*";/d'
  [ "$mode" = nixos ] || profile_expr=''
  sed -i \
    -e '/^ *inputs\.private\.url = /d' \
    -e '/^ *inherit private;$/d' \
    -e 's|{ *central, *private, *\.\.\. *}:|{ central, ... }:|' \
    ${profile_expr:+-e "$profile_expr"} \
    "$flake"
}
