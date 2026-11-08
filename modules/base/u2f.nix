# Signing in with a U2F/FIDO2 security key (e.g. a YubiKey) as an alternative
# to the password, at the graphical login screen and the lock screen of every
# desktop. Console login, sudo and every other PAM service stay password-only:
# the global switch security.pam.u2f.enable stays off (it would add pam_u2f to
# every service), and only the services below get the rule.
#
# Keys are enrolled per user in ~/.config/Yubico/u2f_keys (README, "Signing in
# with a security key") for one fleet-wide origin, so the same file works on
# all of the user's machines. Changing the origin invalidates every enrollment.
{ config, lib, pkgs, ... }:
let
  inherit (config.nixos-central) desktop;
  origin = "pam://nixos-central";

  # SDDM and gdm-password don't use the default rules (their whole auth stack
  # is `substack login`), so u2f.enable has no effect on them. This is the
  # default u2f rule of pam.nix written out, placed before the substack: a
  # touch ends the auth stack (sufficient); no key, no enrollment or a timeout
  # fall through to the unchanged login substack, i.e. the password. The order
  # is relative to the login rule, so evaluation fails if nixpkgs drops it.
  u2fBeforeLogin = service: {
    security.pam.services.${service}.rules.auth.u2f = {
      control = "sufficient";
      modulePath = "${pkgs.pam_u2f}/lib/security/pam_u2f.so";
      order = config.security.pam.services.${service}.rules.auth.login.order - 10;
      inherit (config.security.pam.u2f) settings;
    };
  };
in
{
  config = lib.mkMerge [
    (lib.mkIf (desktop != "none") {
      # Used by the rules below, also when the global switch is off. The default
      # authfile is ~/.config/Yubico/u2f_keys.
      security.pam.u2f.settings = {
        inherit origin;
        appid = origin;
        cue = true; # "Please touch the device."
      };

      # pamu2fcfg for enrollment (the global switch would add it otherwise).
      environment.systemPackages = [ pkgs.pam_u2f ];
    })

    # Login screens: whichever display manager is actually enabled, so a
    # machine that switches it (e.g. GDM on kde) keeps key login. GNOME's lock
    # screen also authenticates via gdm-password.
    (lib.mkIf (desktop != "none" && config.services.displayManager.sddm.enable) (u2fBeforeLogin "sddm"))
    (lib.mkIf (desktop != "none" && config.services.displayManager.gdm.enable) (u2fBeforeLogin "gdm-password"))

    # KDE's lock screen (kscreenlocker) has its own service with the default
    # rules, where the u2f rule already sits before pam_unix. Only on kde, so
    # the service isn't created on other desktops.
    (lib.mkIf (desktop == "kde") {
      security.pam.services.kde.u2f.enable = true;
    })

    # Noctalia's lock screen uses the PAM service named in NOCTALIA_PAM_SERVICE
    # and falls back to `login` without it (Modules/LockScreen/LockContext.qml),
    # which stays password-only. A service of its own with the default rules
    # (u2f before pam_unix). If Noctalia renames the variable, unlocking with a
    # key silently stops working, while the password keeps working.
    (lib.mkIf (desktop == "niri-noctalia") {
      security.pam.services.noctalia.u2f.enable = true;
      systemd.user.services.noctalia-shell.environment.NOCTALIA_PAM_SERVICE = "noctalia";
    })
  ];
}
