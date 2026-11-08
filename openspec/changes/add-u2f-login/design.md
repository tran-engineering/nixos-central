# Design

## Context

See proposal.md (Why) and specs/security-key-login/spec.md for the required behavior. The facts below about the pinned nixpkgs (nixos-26.05) and Noctalia shape the approach:

- **Turning U2F on globally reaches every service.** `security.pam.services.<name>.u2f.enable` defaults to `config.security.pam.u2f.enable`. Setting the global switch would therefore add pam_u2f to every PAM service, including `login` (TTY) and `sudo`, which the spec excludes. The generated `u2f` rule takes its settings from `security.pam.u2f.settings` whether or not the global switch is on.
- **GDM's login service has no auth rules of its own.** `gdm-password` (GDM is the login screen of every desktop since `use-gdm-login`) sets `useDefaultRules = false`. Its whole auth stack is a single `substack login` rule. Enabling `u2f.enable` on it would do nothing, and enabling it on `login` would also cover TTY login. GNOME's lock screen authenticates through `gdm-password` as well.
- **KDE's lock screen has its own service.** The `kde` service (kscreenlocker) uses the default rules, so `u2f.enable` works there directly. In the default rule list the u2f rule comes before pam_unix.
- **Noctalia's lock screen uses `login` unless told otherwise.** It reads the PAM service name from `NOCTALIA_PAM_SERVICE` and otherwise probes `/etc/pam.d/login` first, so on NixOS it uses `login`.
- **Existing module patterns.** Base modules gate desktop-dependent configuration on `config.nixos-central.desktop` (see `modules/base/graphical.nix`). Noctalia runs as `systemd.user.services.noctalia-shell`, defined in `modules/desktops/niri-noctalia.nix`.

## Goals / Non-Goals

**Goals:**
- Implement the spec with one module that shows every place U2F is wired in.
- Keep `login`, `sudo` and every other PAM service byte-for-byte as they are today.
- Have CI guard both the services that must contain pam_u2f and those that must not.

**Non-Goals:**
- A `nixos-central` subcommand or installer step for enrollment. The README command is enough for now.
- Declarative key mappings in profiles or overlays.
- Requiring a PIN, 2FA mode, LUKS unlock with FIDO2, and polkit prompts.

## Decisions

### D1: One base module, `modules/base/u2f.nix`, gated on the desktop
The module is imported from `modules/base/default.nix`. All its configuration sits inside `lib.mkIf (config.nixos-central.desktop != "none")`, and the per-desktop parts are nested `mkIf`s.
- *Alternative*: spread the pieces over `kde.nix`, `gnome.nix` and `niri-noctalia.nix`. That fits the existing per-desktop modules, but the security-relevant PAM wiring would end up in three files and be harder to audit. I chose one file.

### D2: Leave `security.pam.u2f.enable` off and enable U2F per service
`security.pam.u2f.settings` is set globally, and only the target services get the rule. This is what keeps `login` and `sudo` untouched without having to opt every other service out with `u2f.enable = false`. An opt-out list would silently miss services that NixOS or a desktop adds later.
- `security.pam.u2f.settings`: `origin = "pam://nixos-central"`, `appid = "pam://nixos-central"`, `cue = true`. The default `authfile` already points to `~/.config/Yubico/u2f_keys`.
- `security.pam.u2f.control` stays `sufficient`.
- The global switch normally adds `pkgs.pam_u2f` to `environment.systemPackages`. With it off, the module adds the package itself so that `pamu2fcfg` is available.

### D3: `gdm-password` gets an explicit `u2f` auth rule before the `login` substack
For example:
```nix
security.pam.services.gdm-password.rules.auth.u2f = {
  control = "sufficient";
  modulePath = "${pkgs.pam_u2f}/lib/security/pam_u2f.so";
  order = config.security.pam.services.gdm-password.rules.auth.login.order - 10;
  settings = config.security.pam.u2f.settings;
};
```
The order is relative to the `login` rule, as pam.nix recommends, so a nixpkgs renumbering cannot silently move it. If the touch succeeds, `sufficient` ends the auth stack. If it fails because no key is plugged in, the user has no enrollment file, or the touch times out, PAM falls through to the unchanged `login` substack, which checks the password. Account and session stacks are not touched.

The rule goes on `gdm-password` on every graphical desktop; on gnome it also covers GNOME's lock screen. Building the rule by hand duplicates what the default u2f rule contains (module path and settings), but nixpkgs offers no switch for services that don't use the default rules.
- *Alternative*: enable U2F on `login`. That is one line and covers the DMs and Noctalia automatically, but it also enables U2F on TTY login, which goes against the spec. I'm recording it here in case the decision about TTY login is revisited.

### D4: KDE lock screen via `security.pam.services.kde.u2f.enable = true`
This applies only when the desktop is kde. The guard keeps the `kde` service from being created on other desktops.

### D5: Noctalia gets its own PAM service, `noctalia`
`security.pam.services.noctalia = { u2f.enable = true; }` builds a normal default-rules service (pam_unix auth plus u2f before it). `systemd.user.services.noctalia-shell.environment.NOCTALIA_PAM_SERVICE = "noctalia"` points the lock screen at it. Both settings apply only when the desktop is niri-noctalia. The environment setting merges into the service already defined in `niri-noctalia.nix`.
- *Alternative*: let Noctalia use `login` and add U2F there. Rejected for the same reason as in D3.

### D6: One fleet-wide origin, `pam://nixos-central`
pam_u2f binds credentials to the origin, which defaults to `pam://<hostname>`. A shared value makes one `u2f_keys` line work on every machine. Pinning it now matters because changing the origin later invalidates every enrollment.

The enrollment command documented in the README must pass `-o pam://nixos-central -i pam://nixos-central`. A plain `pamu2fcfg` would use the hostname origin and produce credentials that don't match.

### D7: Tests as evaluation checks on the generated `/etc/pam.d` text
The checks go in `nixos-central-internal/tests/default.nix`. They evaluate hosts via `testHost` or `central.hostModules` and assert on `config.security.pam.services.<svc>.text`, the exact text written to `/etc/pam.d/<svc>` (`environment.etc."pam.d/<svc>".text` is null in this nixpkgs):
- every graphical desktop: `gdm-password` contains `pam_u2f.so`, ahead of the `login` substack.
- kde: `kde` contains `pam_u2f.so` before `pam_unix.so`.
- niri-noctalia: `noctalia` contains `pam_u2f.so`, and the `noctalia-shell` user service has `NOCTALIA_PAM_SERVICE=noctalia`.
- All four desktops: `login`, `sudo` and `su` do not contain `pam_u2f`.
- none: no `pam.d` file contains `pam_u2f`.
- All settings contain `origin=pam://nixos-central`.

A VM boot test can't exercise a key touch, because the NixOS test framework has no FIDO device emulation. Key behavior is therefore verified by hand on hardware (see tasks).

## Risks / Trade-offs

- **[Prompt order]** GDM starts PAM when the account is picked and shows the cue. KDE's lock screen accepts the touch in the background but unlocks only after *Unlock* is clicked (seen on hardware). Noctalia's lock screen likely needs an empty field and Enter first. (SDDM started PAM only after Enter and showed no cue, which led to `use-gdm-login`.) → The README explains this per desktop. Hardware verification confirms the actual behavior.
- **[Delay when the key is enrolled but unplugged]** pam_u2f fails fast when no device is present, so the password path is not slowed down. → Verified by hand: password login with the key unplugged must not be noticeably slower.
- **[Stolen key unlocks the session]** This was accepted by the user (no PIN). → The README describes the trade-off and how to remove a key. Upgrading to `pinverification` later requires re-enrolling with `-N`.
- **[nixpkgs changes the DM PAM stacks]** For example, the `login` rule could be renamed or the DMs could switch to default rules. → The evaluation fails loudly if `rules.auth.login` disappears, because the order expression references it. The order checks in D7 catch silent reordering.
- **[Noctalia renames `NOCTALIA_PAM_SERVICE`]** Its lock screen would then quietly fall back to `login`, which is password-only, so nothing becomes insecure but U2F unlock stops working. → Only hardware verification catches this. It is noted in a module comment.
- **[Encrypted or unavailable home at login]** `~/.config/Yubico/u2f_keys` can't be read before the home is mounted. This doesn't apply here, because homes are on the LUKS root that is already unlocked at boot.

## Migration Plan

Nothing to migrate. After the update, users without a key see no change. Users who want key login enroll as described in the README. Rollback is reverting the module or booting the previous generation, and enrollment files are simply ignored in that case.
