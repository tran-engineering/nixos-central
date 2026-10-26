# Test profile used by CI: every shared module, picked by name like a private
# overlay does (centralModules), with fish as login shell.
# Profiles named ci-* are test-only: they are not offered by home-only.sh.
{ centralModules, ... }:
{
  imports = [ ../_default ] ++ builtins.attrValues centralModules;
  nixos-central.shell = "fish";
}
