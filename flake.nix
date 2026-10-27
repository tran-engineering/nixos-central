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
    # programs.plasma.* (KDE settings) for every profile and private overlay.
    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
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
        # Shared home modules on ARM (via the ci-modules profile).
        ci-home-modules-aarch64 = ciHome {
          system = "aarch64-linux";
          profile = "ci-modules";
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
        # Every shared module (via the ci-modules profile), evaluated only:
        # on NixOS and as a standalone home.
        // {
          host-eval-ci-modules = evalOnly "host-eval-ci-modules" (ciHost "ci-modules" {
            desktop = "none";
            user = "ci-modules";
            inherit system;
          }).config.system.build.toplevel;
          home-eval-ci-modules = evalOnly "home-eval-ci-modules" (ciHome {
            inherit system;
            profile = "ci-modules";
          }).activationPackage;
        }
        // (
          let
            pkgs = nixpkgs.legacyPackages.${system};
            # Test overlay as a flake object (pure evaluation can't getFlake a path).
            testOverlay = (import ./nixos-central-internal/tests/overlay/flake.nix).outputs { } // {
              inputs = { };
            };
            overlayHost = ciHost "ci-overlay" {
              desktop = "none";
              inherit system;
              private = testOverlay;
            };
            # The names overlays rely on; changing them breaks overlays (announce it).
            expectedModules = [
              "dev-cli"
              "dev-desktop"
              "drawio"
              "fish"
              "foot"
              "general-tools"
              "ghostty"
              "git"
              "godot"
              "idea"
              "jj"
              "zsh"
            ];
            actualModules = builtins.attrNames centralLib.centralModules;
          in
          {
            central-modules =
              assert nixpkgs.lib.assertMsg (actualModules == expectedModules)
                "centralModules changed: ${toString actualModules}. Update expectedModules in flake.nix and announce removed or renamed names as breaking.";
              pkgs.writeText "central-modules" (toString actualModules);

            # The overlay reaches the system, the user's home and centralModules.
            overlay-eval =
              let
                hm = overlayHost.config.home-manager.users.ci-user;
              in
              assert overlayHost.config.environment.etc."nixos-central-overlay-test".text == "from the overlay\n";
              assert hm.home.file.".nixos-central-overlay-test".text == "from the overlay\n";
              assert hm.programs.fish.enable;
              evalOnly "overlay-eval" overlayHost.config.system.build.toplevel;

            # The overlay profile is chosen by user (NixOS) or profile fact
            # (standalone), with homeModules.default as fallback.
            overlay-profiles =
              let
                profileOverlay = withDefault: {
                  inputs = { };
                  homeModules = {
                    ci-user.home.file.overlay-profile.text = "ci-user";
                    kt.home.file.overlay-profile.text = "kt";
                  }
                  // nixpkgs.lib.optionalAttrs withDefault { default.home.file.overlay-profile.text = "default"; };
                };
                hostFile =
                  user: withDefault:
                  (ciHost "ci-overlay" {
                    desktop = "none";
                    inherit system user;
                    private = profileOverlay withDefault;
                  }).config.home-manager.users.${user}.home.file.overlay-profile.text;
                home =
                  profile: withDefault:
                  (centralLib.mkHome {
                    user = "ci-home";
                    homeDirectory = "/home/ci-home";
                    stateVersion = centralLib.release;
                    inherit system profile;
                    private = profileOverlay withDefault;
                  }).config;
                missingWarning = cfg: builtins.any (nixpkgs.lib.hasInfix "does not exist") cfg.warnings;
              in
              assert hostFile "ci-user" true == "ci-user";
              assert hostFile "nobodyhere" true == "default";
              assert !(builtins.tryEval (hostFile "nobodyhere" false)).success;
              assert (home "kt" false).home.file.overlay-profile.text == "kt";
              assert !(missingWarning (home "kt" false));
              assert missingWarning (home "nobodyhere" true);
              pkgs.writeText "overlay-profiles" "ok";

            # Overlays with inputs are refused.
            overlay-rejects-inputs =
              assert
                !(builtins.tryEval
                  (centralLib.mkHome {
                    user = "ci-home";
                    homeDirectory = "/home/ci-home";
                    stateVersion = centralLib.release;
                    inherit system;
                    private = testOverlay // {
                      inputs.nixpkgs = nixpkgs;
                    };
                  }).activationPackage.drvPath
                ).success;
              pkgs.writeText "overlay-rejects-inputs" "ok";
          }
        )
        # Other platforms are only evaluated, not built.
        // nixpkgs.lib.mapAttrs' (
          name: home: nixpkgs.lib.nameValuePair "home-eval-${name}" (evalOnly "home-eval-${name}" home.activationPackage)
        ) (nixpkgs.lib.filterAttrs (_: home: home.pkgs.stdenv.hostPlatform.system != system) self.homeConfigurations)
        // (import ./nixos-central-internal/tests { inherit inputs system; }).checks
      );

      # Tests that boot full desktops, run on demand (README, "Development"):
      # nix build .#desktopTests.reboot-notify-kde
      legacyPackages = forAllSystems (system: {
        desktopTests = (import ./nixos-central-internal/tests { inherit inputs system; }).desktop;
      });
    };
}
