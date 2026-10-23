{
  description = "nixos-central: one central NixOS configuration for many machines";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
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
      centralLib = import ./lib { inherit inputs; };

      # Sample machines, built in CI. Not meant to be installed.
      ciHost =
        name: args:
        centralLib.mkHost (
          {
            hostname = name;
            user = "ci-user";
            disk = "/dev/vda";
            stateVersion = centralLib.release;
            modules = [ ./tests/ci-hardware.nix ];
          }
          // args
        );
    in
    {
      # Entry point for machine flakes: central.lib.mkHost { ... }
      lib = centralLib;

      # Copied to /etc/nixos by the installer.
      templates.host = {
        path = ./templates/host;
        description = "Machine flake for a nixos-central host";
      };

      nixosConfigurations = {
        ci-kde = ciHost "ci-kde" { desktop = "kde"; };
        ci-none = ciHost "ci-none" { desktop = "none"; };
        ci-default-profile = ciHost "ci-default-profile" {
          desktop = "none";
          user = "nobodyhere";
        };
      };

      packages = forAllSystems (system: {
        # Used by the installer: nix run github:tran-engineering/nixos-central#disko
        inherit (disko.packages.${system}) disko;
        installer = nixpkgs.legacyPackages.${system}.writeShellScriptBin "nixos-central-install" (
          builtins.readFile ./installer/install.sh
        );
      });

      checks = forAllSystems (
        system:
        nixpkgs.lib.mapAttrs' (
          name: host: nixpkgs.lib.nameValuePair "host-${name}" host.config.system.build.toplevel
        ) (nixpkgs.lib.filterAttrs (_: host: host.pkgs.stdenv.hostPlatform.system == system) self.nixosConfigurations)
        // import ./tests { inherit inputs system; }
      );
    };
}
