{ inputs }:
let
  inherit (inputs) nixpkgs home-manager disko;
  inherit (nixpkgs) lib;

  # All NixOS modules of a machine, without evaluating them (also used by tests).
  hostModules =
    {
      hostname,
      user,
      desktop,
      disk,
      stateVersion,
      modules ? [ ],
      system ? "x86_64-linux",
    }:
    [
      disko.nixosModules.disko
      home-manager.nixosModules.home-manager
      ../../modules/options.nix
      ../disko
      ../../modules/base
      ../../modules/desktops.nix
      ../../modules/user.nix
      {
        nixpkgs.hostPlatform = system;
        system.stateVersion = stateVersion;
        nixos-central = {
          inherit
            hostname
            user
            desktop
            disk
            ;
        };
      }
    ]
    ++ modules;
in
{
  inherit hostModules;

  desktopNames = import ./desktop-names.nix;

  # Profiles offered by home-only.sh (see profiles.nix).
  profileNames = (import ./profiles.nix).names;

  # NixOS release of the pinned nixpkgs, e.g. "26.05". The installer writes it
  # into new machine flakes as their stateVersion.
  release = lib.trivial.release;

  # Build a complete machine from its facts. This is the only interface machine
  # flakes depend on; keep it backwards compatible.
  mkHost =
    args:
    lib.nixosSystem {
      specialArgs = { inherit inputs; };
      modules = hostModules args;
    };

  # Build a standalone home (Linux without NixOS) from its facts. This is the
  # only interface ~/.config/home-manager flakes depend on; keep it backwards
  # compatible. `profile` defaults to the profile named like `user`.
  mkHome =
    {
      user,
      homeDirectory,
      stateVersion,
      system ? "x86_64-linux",
      profile ? null,
      nvidia ? null, # { version; sha256; } of the host's driver
    }:
    let
      shared = import ./nixpkgs.nix { inherit inputs; };
      resolved = (import ./profiles.nix).resolve (if profile == null then user else profile);
      # Recording the host's NVIDIA driver means using it, which requires its license.
      nixpkgsConfig = shared.config // lib.optionalAttrs (nvidia != null) { nvidia.acceptLicense = true; };
    in
    home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs {
        inherit system;
        config = nixpkgsConfig;
        overlays = [ (shared.unstableOverlay nixpkgsConfig) ];
      };
      modules = [
        resolved.path
        ../../modules/home/standalone.nix
        {
          home.username = user;
          home.homeDirectory = homeDirectory;
          home.stateVersion = stateVersion;
          warnings = lib.optional (profile != null && resolved.fallback) ''
            nixos-central: profile "${profile}" does not exist in the central repository; using the default profile.
            Choose another one in ~/.config/home-manager/flake.nix (available: ${toString (import ./profiles.nix).names}).
          '';
        }
        (lib.mkIf (nvidia != null) {
          targets.genericLinux.gpu.nvidia = {
            enable = true;
            inherit (nvidia) version sha256;
          };
        })
      ];
    };
}
