# nixpkgs settings shared by NixOS machines (modules/base) and standalone
# homes (lib.mkHome), so both see the same package set.
{ inputs }:
{
  config = {
    allowUnfree = true;
    # pkgs.unstable.logseq is built on this end-of-life Electron. Only this
    # exact version is allowed; update or remove it when nixos-unstable's
    # logseq moves on (evaluation of a profile with logseq fails until then).
    permittedInsecurePackages = [ "electron-39.8.10" ];
  };

  # pkgs.unstable: packages from the nixpkgs-unstable input, with the given
  # nixpkgs config. Lazy: only evaluated when something uses it.
  unstableOverlay =
    nixpkgsConfig: final: _: {
      unstable = import inputs.nixpkgs-unstable {
        inherit (final.stdenv.hostPlatform) system;
        config = nixpkgsConfig;
      };
    };
}
