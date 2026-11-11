# Installation image (README, "Install"): the minimal NixOS installation image
# plus a start-up prompt on the first console that runs the current installer
# from the central repository (start.sh). Built as packages.x86_64-linux.iso,
# published by .github/workflows/iso.yml and booted by tests/e2e.
#
# Not a nixosConfigurations entry: CI builds every one of those on each push.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  start = pkgs.writeShellApplication {
    name = "nixos-central-start";
    runtimeInputs = [
      pkgs.curl
      pkgs.gum # yes/no menus
      pkgs.networkmanager # nmtui
      config.nix.package
    ];
    text = builtins.readFile ./start.sh;
  };
in
{
  imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix" ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # nixos-central-<release>-x86_64.iso. The squashfs keeps the image module's
  # default zstd compression.
  image.baseName = lib.mkForce "nixos-central-${config.system.nixos.release}-${pkgs.stdenv.hostPlatform.uname.processor}";

  # gum: the installer's menus, and nom: its build progress display, without
  # fetching them first.
  environment.systemPackages = [
    start
    pkgs.gum
    pkgs.nix-output-monitor
  ];

  # Offer the installer on the first console only. Serial consoles, SSH and
  # the other virtual consoles stay plain shells.
  programs.bash.loginShellInit = ''
    if [ "$(tty)" = /dev/tty1 ] && [ "$USER" = nixos ] && [ -z "''${NIXOS_CENTRAL_START_OFFERED:-}" ]; then
      export NIXOS_CENTRAL_START_OFFERED=1
      nixos-central-start || true
    fi
  '';

  services.getty.helpLine = lib.mkAfter ''

    To install nixos-central, run `nixos-central-start`.
  '';
}
