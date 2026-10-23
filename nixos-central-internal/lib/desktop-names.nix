# Names of the available desktops: one per modules/desktops/<name>.nix.
# Uses builtins only, so the installer can list desktops cheaply.
let
  entries = builtins.readDir ../../modules/desktops;
  files = builtins.filter (
    name: entries.${name} == "regular" && builtins.match ".*\\.nix" name != null
  ) (builtins.attrNames entries);
in
map (name: builtins.head (builtins.match "(.*)\\.nix" name)) files
