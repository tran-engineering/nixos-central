# Test profile used by CI: overrides one setting of the base configuration
# (modules/home/base.nix) without mkForce. Test profiles are added only by the
# CI configurations in flake.nix; machines and homes can't select them.
{
  home.sessionVariables.EDITOR = "nano";
}
