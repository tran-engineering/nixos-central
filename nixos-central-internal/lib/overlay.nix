# Private overlays (README, "Private overlay"): a flake without inputs that
# exports homeModules.<profile> (optionally homeModules.default as fallback)
# and optionally nixosModules.default.
{ lib }:
let
  homeDir = ../../modules/home;
  # Part of every profile, set up by central itself; not for profiles to pick.
  internal = [
    "standalone.nix"
    "shell.nix"
    "private.nix"
    "update-notice.nix"
  ];
  entries = lib.filterAttrs (name: _: !(builtins.elem name internal)) (builtins.readDir homeDir);
in
{
  # Shared home modules by name (dev-cli, fish, ...), passed to every profile
  # and overlay as the special argument `centralModules`. The names are an
  # interface: renaming or removing one breaks overlays.
  centralModules = lib.mapAttrs' (
    name: _: lib.nameValuePair (lib.removeSuffix ".nix" name) (homeDir + "/${name}")
  ) entries;

  # The overlay, checked; throws with an explanation if it isn't a valid overlay.
  check =
    private:
    if (private.inputs or { }) != { } then
      throw "nixos-central: the private overlay must not declare inputs (it has: ${toString (builtins.attrNames private.inputs)}). Overlays only export modules; packages come from the central repository."
    else if (private.homeModules or { }) == { } then
      throw "nixos-central: the private overlay must export homeModules (one module per profile)."
    else
      private;

  # The overlay's module for profile `name`: homeModules.<name>, else
  # homeModules.default. Never silently none: a missing profile fails the build.
  homeModule =
    private: name:
    private.homeModules.${name} or private.homeModules.default or (throw
      "nixos-central: the private overlay has no profile \"${name}\" and no default profile (it has: ${toString (builtins.attrNames private.homeModules)})."
    );
}
