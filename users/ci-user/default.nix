# Test profile used by CI: reuses the default and overrides one setting.
{ lib, ... }:
{
  imports = [ ../_default ];
  home.sessionVariables.EDITOR = lib.mkForce "nano";
}
