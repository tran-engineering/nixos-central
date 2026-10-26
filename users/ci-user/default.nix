# Test profile used by CI: reuses the default and overrides one setting.
# Profiles named ci-* are test-only: they are not offered by home-only.sh.
{ lib, ... }:
{
  imports = [ ../_default ];
  home.sessionVariables.EDITOR = lib.mkForce "nano";
}
