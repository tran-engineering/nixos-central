{ inputs }:
let
  inherit (inputs) nixpkgs home-manager disko;
  inherit (nixpkgs) lib;
  overlay = import ./overlay.nix { inherit lib; };
  keyboardLayouts = import ./keyboard-layouts.nix;

  # Profiles come only from the private overlay; a recorded profile selects the
  # overlay's homeModules.<profile>. Warnings where a recorded profile has no
  # effect. "_default" was written by earlier home installers and is treated as
  # if no profile were recorded.
  profileWarnings =
    {
      profile,
      private, # checked overlay, or null
      flakePath,
    }:
    let
      recorded = profile != null && profile != "_default";
    in
    lib.optional (recorded && private == null) ''
      nixos-central: profile "${profile}" has no effect without a private overlay (profiles come only from the overlay).
      Remove the profile line from ${flakePath}, or add an overlay: nixos-central private setup [<flake-url>] --profile ${profile}
    ''
    ++ lib.optional (recorded && private != null && !(private.homeModules ? ${profile}) && private.homeModules ? default) ''
      nixos-central: the private overlay has no profile "${profile}"; using its default profile.
      Choose another one in ${flakePath} (overlay profiles: ${toString (builtins.attrNames private.homeModules)}).
    '';

  # Home modules every primary user and standalone home gets from central.
  baseHomeModules = [
    ../../modules/home/base.nix
    ../../modules/home/shell.nix
    ../../modules/home/private.nix
    ../../modules/home/command.nix
    ../../modules/home/update-notice.nix
    ../../modules/home/gc.nix
    inputs.plasma-manager.homeModules.plasma-manager
  ];

  # All NixOS modules of a machine, without evaluating them (also used by tests).
  hostModules =
    {
      hostname,
      user,
      desktop,
      disk,
      stateVersion,
      keyboardLayout ? "us", # one of the names in keyboard-layouts.nix
      nvidia ? null, # the NVIDIA GPU (modules/options.nix), or null
      modules ? [ ],
      system ? "x86_64-linux",
      private ? null, # private overlay flake (README, "Private overlay")
      profile ? null, # overlay profile in place of `user`; like mkHome
    }:
    let
      checked = overlay.check private;
      name = if profile == null then user else profile;
    in
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
            keyboardLayout
            nvidia
            profile
            ;
        };
        home-manager.extraSpecialArgs = { inherit (overlay) centralModules; };
        warnings = profileWarnings {
          inherit profile;
          private = if private == null then null else checked;
          flakePath = "/etc/nixos/flake.nix";
        };
      }
    ]
    ++ lib.optionals (private != null) (
      [
        {
          nixos-central.private.enable = true;
          home-manager.users.${user} = {
            imports = [ (overlay.homeModule checked name) ];
            nixos-central.private.enable = true;
          };
        }
      ]
      ++ lib.optional (checked ? nixosModules.default) checked.nixosModules.default
    )
    ++ modules;

  # Arguments of home-manager's homeManagerConfiguration for a standalone home,
  # without evaluating it (also used by tests to add a test profile).
  homeConfigArgs =
    {
      user,
      homeDirectory,
      stateVersion,
      system ? "x86_64-linux",
      profile ? null,
      nvidia ? null, # { version; sha256; } of the host's driver
      private ? null, # private overlay flake (README, "Private overlay")
    }:
    let
      shared = import ./nixpkgs.nix { inherit inputs; };
      name = if profile == null then user else profile;
      checked = if private == null then null else overlay.check private;
      # Recording the host's NVIDIA driver means using it, which requires its license.
      nixpkgsConfig = shared.config // lib.optionalAttrs (nvidia != null) { nvidia.acceptLicense = true; };
    in
    {
      pkgs = import nixpkgs {
        inherit system;
        config = nixpkgsConfig;
        overlays = [ (shared.unstableOverlay nixpkgsConfig) ];
      };
      extraSpecialArgs = { inherit (overlay) centralModules; };
      modules =
        baseHomeModules
        ++ [
          ../../modules/home/standalone.nix
          {
            home.username = user;
            home.homeDirectory = homeDirectory;
            home.stateVersion = stateVersion;
            warnings = profileWarnings {
              inherit profile;
              private = checked;
              flakePath = "~/.config/home-manager/flake.nix";
            };
          }
          (lib.mkIf (nvidia != null) {
            targets.genericLinux.gpu.nvidia = {
              enable = true;
              inherit (nvidia) version sha256;
            };
          })
        ]
        ++ lib.optionals (private != null) [
          (overlay.homeModule checked name)
          { nixos-central.private.enable = true; }
        ];
    };
in
{
  inherit hostModules homeConfigArgs;

  desktopNames = import ./desktop-names.nix;

  # Keyboard layouts the installer offers, and how each maps to the console and
  # the graphical session (see keyboard-layouts.nix).
  inherit keyboardLayouts;
  keyboardLayoutNames = builtins.attrNames keyboardLayouts;

  # Shared home modules by name, as profiles and overlays get them.
  inherit (overlay) centralModules;

  # Used by the installer to set up a private overlay (README, "Private overlay"):
  # the default overlay URL, GitHub's SSH host key, and the shell functions that
  # add the overlay to a flake, shared with `nixos-central private`.
  defaultPrivate = import ./default-private.nix;
  githubHostKey = import ./github-host-key.nix;
  privateFlakeEdit = ../private/flake-edit.sh;

  # Used by the installer: prints the nvidia fact for the machine it runs on.
  nvidiaDetect = ../installer/detect-nvidia.sh;

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
  # compatible. `profile` selects the private overlay's profile; it defaults to
  # the one named like `user`.
  mkHome = args: home-manager.lib.homeManagerConfiguration (homeConfigArgs args);
}
