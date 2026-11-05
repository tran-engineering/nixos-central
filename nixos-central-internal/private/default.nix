# The `nixos-central private` subcommand (README, "Private overlay"), for NixOS
# machines (modules/base/private.nix) and standalone homes (standalone.nix).
{ writeShellApplication }:
writeShellApplication {
  name = "nixos-central-private";
  text = ''
    GITHUB_HOST_KEY=${builtins.toJSON (import ../lib/github-host-key.nix)}
    DEFAULT_URL=${builtins.toJSON (import ../lib/default-private.nix)}
  ''
  + builtins.readFile ./nixos-central-private.sh;
}
