# Spec Delta

## ADDED Requirements

### Requirement: Profiles can configure KDE Plasma
Profiles and private overlays SHALL be able to set KDE Plasma settings (theme, shortcuts, input devices, configuration files) declaratively, on NixOS machines and standalone homes. Setting none MUST leave the environment unchanged.

#### Scenario: Overlay sets Plasma shortcuts
- **WHEN** kt's overlay sets a Plasma shortcut and a dark color scheme
- **THEN** after the next update, kt's Plasma session uses that shortcut and color scheme

#### Scenario: Profile without Plasma settings
- **WHEN** a profile sets no Plasma settings
- **THEN** no Plasma configuration files are written for that user

### Requirement: Logseq from unstable is installable
A profile or overlay SHALL be able to install `pkgs.unstable.logseq` without additional configuration, even though it depends on an Electron release nixpkgs marks insecure. The permitted exception MUST be limited to that Electron release.

#### Scenario: Install logseq
- **WHEN** an overlay adds `pkgs.unstable.logseq` to its packages
- **THEN** the home builds and logseq starts

#### Scenario: Other insecure packages
- **WHEN** a profile adds a package marked insecure other than that Electron release
- **THEN** evaluation fails as it does without the exception
