# Profiles in users/ (home-manager modules), shared by NixOS machines
# (modules/user.nix) and standalone homes (lib.mkHome).
let
  usersDir = ../../users;
  exists = name: builtins.pathExists (usersDir + "/${name}");
in
{
  # Profile for `name`: users/<name> if the central repo has one, users/_default
  # otherwise. Evaluated on every build, so a profile merged later is picked up
  # by the next update.
  resolve =
    name:
    if exists name then
      {
        path = usersDir + "/${name}";
        fallback = false;
      }
    else
      {
        path = usersDir + "/_default";
        fallback = true;
      };

  # Profiles a user can pick for a standalone home: _default first, then the
  # personal profiles. Names starting with "ci-" are test-only and not offered.
  names =
    let
      entries = builtins.readDir usersDir;
      selectable =
        name: entries.${name} == "directory" && name != "_default" && builtins.substring 0 3 name != "ci-";
    in
    [ "_default" ] ++ builtins.filter selectable (builtins.attrNames entries);
}
