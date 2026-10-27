# The nixos-central-private command (README, "Private overlay"), for NixOS
# machines (modules/base/private.nix) and standalone homes (standalone.nix).
{ writeShellApplication }:
writeShellApplication {
  name = "nixos-central-private";
  text = ''
    GITHUB_HOST_KEY=${builtins.toJSON (import ../lib/github-host-key.nix)}
  ''
  + builtins.readFile ./nixos-central-private.sh;
}
