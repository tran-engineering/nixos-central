{
  description = "nixos-central: one central NixOS configuration for many machines";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # Newer packages: pkgs.unstable.<name>; niri and Noctalia on niri-noctalia machines.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ self, nixpkgs, disko, ... }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      # Standalone homes also run on ARM, so their packages exist for both.
      forPackageSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];
      centralLib = import ./nixos-central-internal/lib { inherit inputs; };

      # Sample machines, built in CI. Not meant to be installed.
      ciHost =
        name: args:
        centralLib.mkHost (
          {
            hostname = name;
            user = "ci-user";
            disk = "/dev/vda";
            stateVersion = centralLib.release;
            modules = [ ./nixos-central-internal/tests/ci-hardware.nix ];
          }
          // args
        );

      # Sample standalone homes, built in CI. Not meant to be installed.
      ciHome =
        args:
        centralLib.mkHome (
          {
            user = "ci-home";
            homeDirectory = "/home/${args.user or "ci-home"}";
            stateVersion = centralLib.release;
          }
          // args
        );
    in
    {
      # Entry point for machine flakes: central.lib.mkHost { ... }
      lib = centralLib;

      # Copied to /etc/nixos by the installer.
      templates.host = {
        path = ./nixos-central-internal/templates/host;
        description = "Machine flake for a nixos-central host";
      };

      # Copied to ~/.config/home-manager by home-only.sh.
      templates.home = {
        path = ./nixos-central-internal/templates/home;
        description = "Home flake for a standalone nixos-central home (Linux without NixOS)";
      };

      nixosConfigurations = {
        ci-kde = ciHost "ci-kde" { desktop = "kde"; };
        ci-gnome = ciHost "ci-gnome" { desktop = "gnome"; };
        ci-niri-noctalia = ciHost "ci-niri-noctalia" { desktop = "niri-noctalia"; };
        ci-none = ciHost "ci-none" { desktop = "none"; };
        ci-default-profile = ciHost "ci-default-profile" {
          desktop = "none";
          user = "nobodyhere";
        };
      };

      homeConfigurations = {
        ci-home-default = ciHome { profile = "_default"; };
        # Login name differs from the profile name.
        ci-home-renamed = ciHome {
          user = "ci.user";
          profile = "ci-user";
        };
        ci-home-aarch64 = ciHome { system = "aarch64-linux"; };
        # Shared home modules on ARM (via the kt profile).
        ci-home-kt-aarch64 = ciHome {
          system = "aarch64-linux";
          profile = "kt";
        };
      };

      packages = forPackageSystems (system: {
        # Used by the installer: nix run github:tran-engineering/nixos-central#disko
        inherit (disko.packages.${system}) disko;
        # Used by home-only.sh for the first switch, so it matches the pinned release.
        inherit (inputs.home-manager.packages.${system}) home-manager;
        installer = nixpkgs.legacyPackages.${system}.writeShellScriptBin "nixos-central-install" (
          builtins.readFile ./nixos-central-internal/installer/install.sh
        );
      });

      checks = forAllSystems (
        system:
        let
          # Evaluates a derivation without building it or fetching its inputs.
          # Used where the packages are trusted to nixpkgs' Hydra.
          evalOnly =
            name: drv:
            nixpkgs.legacyPackages.${system}.writeText name (builtins.unsafeDiscardStringContext drv.drvPath);
        in
        nixpkgs.lib.mapAttrs' (
          name: host: nixpkgs.lib.nameValuePair "host-${name}" host.config.system.build.toplevel
        ) (nixpkgs.lib.filterAttrs (_: host: host.pkgs.stdenv.hostPlatform.system == system) self.nixosConfigurations)
        // nixpkgs.lib.mapAttrs' (
          name: home: nixpkgs.lib.nameValuePair "home-${name}" home.activationPackage
        ) (nixpkgs.lib.filterAttrs (_: home: home.pkgs.stdenv.hostPlatform.system == system) self.homeConfigurations)
        # Every selectable profile must also evaluate standalone (no NixOS-only
        # options). Evaluated only: profiles can pull in large closures, and
        # _default is built via ci-home-default.
        // nixpkgs.lib.listToAttrs (
          map (
            profile:
            nixpkgs.lib.nameValuePair "home-profile-${profile}" (
              evalOnly "home-profile-${profile}" (ciHome { inherit system profile; }).activationPackage
            )
          ) centralLib.profileNames
        )
        # Shared home modules on NixOS (via the kt profile), evaluated only.
        // {
          host-eval-kt = evalOnly "host-eval-kt" (ciHost "ci-kt" {
            desktop = "none";
            user = "kt";
            inherit system;
          }).config.system.build.toplevel;
        }
        # Other platforms are only evaluated, not built.
        // nixpkgs.lib.mapAttrs' (
          name: home: nixpkgs.lib.nameValuePair "home-eval-${name}" (evalOnly "home-eval-${name}" home.activationPackage)
        ) (nixpkgs.lib.filterAttrs (_: home: home.pkgs.stdenv.hostPlatform.system != system) self.homeConfigurations)
        // import ./nixos-central-internal/tests { inherit inputs system; }
      );
    };
}
