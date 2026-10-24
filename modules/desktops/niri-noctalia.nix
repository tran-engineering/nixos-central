# niri (scrollable-tiling Wayland compositor) with the Noctalia shell, SDDM login.
# Noctalia runs as a systemd user service in every graphical session, so it
# also starts with a user's own niri config. The default niri config lives in
# ./niri-noctalia/config.kdl and is installed as /etc/niri/config.kdl, which
# niri uses when ~/.config/niri/config.kdl does not exist.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  niri = config.programs.niri.package;
  noctalia = pkgs.noctalia-shell;

  # Fails the build if the config does not parse with this niri version.
  niriConfig = pkgs.runCommand "niri-config.kdl" { nativeBuildInputs = [ niri ]; } ''
    niri validate -c ${./niri-noctalia/config.kdl}
    cp ${./niri-noctalia/config.kdl} $out
  '';

  # Started with and stopped with the graphical session.
  sessionService = description: execStart: {
    inherit description;
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    # Keep the session PATH (imported by niri-session); Noctalia runs `sh` and
    # other tools that the minimal default service PATH lacks.
    enableDefaultPath = false;
    serviceConfig = {
      ExecStart = execStart;
      Restart = "on-failure";
    };
  };
in
{
  config = lib.mkIf (config.nixos-central.desktop == "niri-noctalia") {
    programs.niri.enable = true;
    environment.etc."niri/config.kdl".source = niriConfig;

    services.displayManager = {
      sddm = {
        enable = true;
        wayland.enable = true;
      };
      defaultSession = "niri";
    };
    # The niri module enables gnome-keyring; unlock it with the login password.
    security.pam.services.sddm.enableGnomeKeyring = true;

    systemd.user.services.noctalia-shell = sessionService "Noctalia shell" (lib.getExe noctalia);
    systemd.user.services.polkit-gnome-agent =
      sessionService "Polkit authentication agent" "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";

    # Used by Noctalia's battery and power-profile widgets.
    services.upower.enable = true;
    services.power-profiles-daemon.enable = true;

    environment.systemPackages = [
      noctalia # for the `noctalia-shell ipc call ...` keybindings
      pkgs.alacritty # terminal (Mod+T)
      pkgs.xwayland-satellite # niri starts it on demand for X11 apps
    ];
  };
}
