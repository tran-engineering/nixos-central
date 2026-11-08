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

      # Test profiles (home-manager modules) in nixos-central-internal/tests/profiles,
      # added on top of the base configuration. Only CI configurations use them;
      # machines and homes get profiles from their private overlay.
      testProfilePath = name: ./nixos-central-internal/tests/profiles + "/${name}";

      # Sample machines, built in CI. Not meant to be installed.
      # `testProfile`: test profile for the primary user, or null for none.
      ciHost =
        name:
        {
          testProfile ? "ci-user",
          ...
        }@args:
        let
          host = {
            hostname = name;
            user = "ci-user";
            disk = "/dev/vda";
            stateVersion = centralLib.release;
          }
          // removeAttrs args [ "testProfile" ];
        in
        centralLib.mkHost (
          host
          // {
            modules = [
              ./nixos-central-internal/tests/ci-hardware.nix
            ]
            ++ nixpkgs.lib.optional (testProfile != null) {
              home-manager.users.${host.user}.imports = [ (testProfilePath testProfile) ];
            };
          }
        );

      # Sample standalone homes, built in CI. Not meant to be installed.
      # `testProfile`: test profile on top of the base configuration, or null.
      ciHome =
        {
          testProfile ? null,
          ...
        }@args:
        let
          config = centralLib.homeConfigArgs (
            {
              user = "ci-home";
              homeDirectory = "/home/${args.user or "ci-home"}";
              stateVersion = centralLib.release;
            }
            // removeAttrs args [ "testProfile" ]
          );
        in
        inputs.home-manager.lib.homeManagerConfiguration (
          config
          // {
            modules = config.modules ++ nixpkgs.lib.optional (testProfile != null) (testProfilePath testProfile);
          }
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
      };

      homeConfigurations = {
        # Base configuration only: no profile, no overlay.
        ci-home-default = ciHome { };
        # Login name with a dot, with a test profile on top of the base.
        ci-home-dotted = ciHome {
          user = "ci.user";
          testProfile = "ci-user";
        };
        ci-home-aarch64 = ciHome { system = "aarch64-linux"; };
        # Shared home modules on ARM (via the ci-modules test profile).
        ci-home-modules-aarch64 = ciHome {
          system = "aarch64-linux";
          testProfile = "ci-modules";
        };
      };

      packages = forPackageSystems (
        system:
        {
          # Used by the installer: nix run git+https://github.com/tran-engineering/nixos-central#disko
          inherit (disko.packages.${system}) disko;
          # Used by home-only.sh for the first switch, so it matches the pinned release.
          inherit (inputs.home-manager.packages.${system}) home-manager;
          installer = nixpkgs.legacyPackages.${system}.writeShellScriptBin "nixos-central-install" (
            builtins.readFile ./nixos-central-internal/installer/install.sh
          );
        }
        # Installation image (nixos-central-internal/iso), x86_64 only. Not in
        # `checks`; built by tests/e2e (same modules plus a serial console) and
        # .github/workflows/iso.yml.
        // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
          iso =
            (nixpkgs.lib.nixosSystem {
              modules = [
                ./nixos-central-internal/iso
                { nixpkgs.hostPlatform = system; }
              ];
            }).config.system.build.isoImage;
        }
      );

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
        # Every shared module (via the ci-modules profile), evaluated only:
        # on NixOS and as a standalone home.
        // {
          host-eval-ci-modules = evalOnly "host-eval-ci-modules" (ciHost "ci-modules" {
            desktop = "none";
            user = "ci-modules";
            testProfile = "ci-modules";
            inherit system;
          }).config.system.build.toplevel;
          home-eval-ci-modules = evalOnly "home-eval-ci-modules" (ciHome {
            inherit system;
            testProfile = "ci-modules";
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
              "general-tools"
              "git"
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
              assert hm.programs.zsh.enable;
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
                plainHome =
                  profile:
                  (centralLib.mkHome {
                    user = "ci-home";
                    homeDirectory = "/home/ci-home";
                    stateVersion = centralLib.release;
                    inherit system profile;
                  }).config;
                missingWarning = cfg: builtins.any (nixpkgs.lib.hasInfix "has no profile") cfg.warnings;
                noEffectWarning = cfg: builtins.any (nixpkgs.lib.hasInfix "has no effect without a private overlay") cfg.warnings;
              in
              assert hostFile "ci-user" true == "ci-user";
              assert hostFile "nobodyhere" true == "default";
              assert !(builtins.tryEval (hostFile "nobodyhere" false)).success;
              assert (home "kt" false).home.file.overlay-profile.text == "kt";
              assert !(missingWarning (home "kt" false));
              assert missingWarning (home "nobodyhere" true);
              # Without an overlay: "_default" (earlier home installers) is silent,
              # any other recorded profile warns; both get the base configuration.
              assert !(builtins.any (nixpkgs.lib.hasInfix "nixos-central: ") (plainHome "_default").warnings);
              assert noEffectWarning (plainHome "kt");
              assert (plainHome "kt").home.sessionVariables.EDITOR == "vim";
              pkgs.writeText "overlay-profiles" "ok";

            # A recorded profile (NixOS) selects the overlay profile in place of the
            # user's name; the account keeps the user's name. Without an overlay it
            # has no effect (warning). Everyone gets the base configuration.
            host-profile =
              let
                host =
                  args:
                  (ciHost "ci-profile" (
                    {
                      desktop = "none";
                      user = "alice";
                      testProfile = null;
                      inherit system;
                    }
                    // args
                  )).config;
                hm = cfg: cfg.home-manager.users.alice;
                editor = cfg: (hm cfg).home.sessionVariables.EDITOR;
                hasWarning = text: cfg: builtins.any (nixpkgs.lib.hasInfix text) cfg.warnings;
                overlayProfile = host {
                  profile = "ci-overlay";
                  private = testOverlay;
                };
                withoutOverlay = host { profile = "kt"; };
                none = host { };
                unknown = host {
                  profile = "nosuch";
                  private = testOverlay;
                };
              in
              # (a) Overlay profile on top of the base configuration.
              assert (hm overlayProfile).home.file.".nixos-central-overlay-profile".text == "ci-overlay\n";
              assert editor overlayProfile == "vim";
              assert overlayProfile.users.users.alice.isNormalUser;
              assert (hm overlayProfile).home.username == "alice";
              assert !(hasWarning "nixos-central: " overlayProfile);
              # (b) Recorded profile without overlay: base only, with a warning.
              assert editor withoutOverlay == "vim";
              assert hasWarning "has no effect without a private overlay" withoutOverlay;
              # (c) No profile, no overlay: base only, no warning.
              assert editor none == "vim";
              assert none.nixos-central.profile == null;
              assert !(hasWarning "nixos-central: " none);
              # (d) Profile the overlay lacks: its default profile, with a warning.
              assert (hm unknown).home.file.".nixos-central-overlay-test".text == "from the overlay\n";
              assert hasWarning "has no profile \"nosuch\"" unknown;
              pkgs.writeText "host-profile" "ok";

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
