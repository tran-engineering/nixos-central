# Flatpak with Flathub on every graphical desktop: apps from outside nixpkgs,
# installable without Nix knowledge (Discover on KDE, GNOME Software on GNOME,
# `flatpak install flathub <id>` anywhere). Flatpak apps live in
# /var/lib/flatpak and ~/.local/share/flatpak, outside Nix: they are not part
# of a generation and not rolled back with one.
{ config, inputs, lib, ... }:
let
  flatpak = config.services.flatpak.package;

  # Same schedule as the NixOS upgrade (auto-upgrade.nix), but separate from
  # it: a Flatpak failure never fails the system upgrade, and updated apps are
  # used from their next start, without a reboot. Flatpak deploys atomically,
  # so a failed or offline run leaves the installed versions in place.
  # Also once per start of the service manager (boot for the system, first
  # login for a user), a few minutes in: not wanted by multi-user.target
  # directly, because waiting for the network would hold up the boot.
  updateTimer = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnStartupSec = "5min";
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "30min";
    };
  };
  updateService = installation: {
    description = "Update Flatpak apps and runtimes (${installation} installation)";
    path = [ flatpak ];
    serviceConfig.Type = "oneshot";
    script = ''
      flatpak update --${installation} --noninteractive --assumeyes
    '';
  };
in
{
  # Shared with appimage.nix. Lets the minimal VM test use both without a desktop.
  options.nixos-central.desktopApps.enable = lib.mkOption {
    type = lib.types.bool;
    default = config.nixos-central.desktop != "none";
    defaultText = lib.literalExpression ''config.nixos-central.desktop != "none"'';
    internal = true;
    description = "Whether to provide Flatpak (with Flathub) and AppImage support.";
  };

  config = lib.mkIf config.nixos-central.desktopApps.enable {
    services.flatpak.enable = true;

    # Flathub from the `flathub` input (https://dl.flathub.org/repo/flathub.flatpakrepo:
    # URL and signing key), already in the store: needs no network at boot.
    # A removed remote comes back at the next boot.
    systemd.services.flatpak-flathub = {
      description = "Add the Flathub remote to Flatpak";
      wantedBy = [ "multi-user.target" ];
      path = [ flatpak ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        flatpak remote-add --system --if-not-exists flathub ${inputs.flathub}
      '';
    };

    # Apps installed system-wide (the app stores' and `flatpak install`'s default).
    systemd.services.flatpak-update = lib.recursiveUpdate (updateService "system") {
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
    };
    systemd.timers.flatpak-update = updateTimer;

    # Apps a user installed with `flatpak install --user`, in every user's manager.
    systemd.user.services.flatpak-update = updateService "user";
    systemd.user.timers.flatpak-update = updateTimer;
  };
}
