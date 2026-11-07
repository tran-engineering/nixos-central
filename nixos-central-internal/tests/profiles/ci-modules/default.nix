# Test profile used by CI: every shared module, picked by name like a private
# overlay does (centralModules), with fish as login shell, plus a Plasma
# setting so plasma-manager is evaluated everywhere.
# Test profiles are added only by the CI configurations in flake.nix.
{ centralModules, ... }:
{
  imports = builtins.attrValues centralModules;
  nixos-central.shell = "fish";
  programs.plasma = {
    enable = true;
    configFile.kdeglobals.General.TerminalApplication = "konsole";
  };
}
