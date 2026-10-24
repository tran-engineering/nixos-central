# Spec Delta

## MODIFIED Requirements

### Requirement: Desktop is selectable per machine
The central repository SHALL offer a set of named desktops, including `kde`, `gnome`, `niri-noctalia` and `none`. The machine flake's desktop value SHALL determine which desktop environment is enabled. An unknown desktop name MUST fail evaluation with a message listing valid names.

#### Scenario: KDE selected
- **WHEN** a machine flake sets desktop `kde`
- **THEN** the system boots into a graphical KDE Plasma login

#### Scenario: GNOME selected
- **WHEN** a machine flake sets desktop `gnome`
- **THEN** the system boots into the graphical GDM login, and logging in starts a GNOME Wayland session

#### Scenario: niri with Noctalia selected
- **WHEN** a machine flake sets desktop `niri-noctalia`
- **THEN** the system boots into the graphical SDDM login, and logging in starts a niri session in which the Noctalia shell is running

#### Scenario: Change desktop later
- **WHEN** a user changes the desktop value in `/etc/nixos/flake.nix` to another offered desktop and rebuilds
- **THEN** the new desktop is active after rebuild

#### Scenario: Invalid desktop
- **WHEN** a machine flake sets desktop `foo`
- **THEN** evaluation fails and lists the valid desktop names

## ADDED Requirements

### Requirement: Graphical desktops share common services
Every graphical desktop (every desktop except `none`) SHALL provide sound, Bluetooth and printing.

#### Scenario: Sound on any graphical desktop
- **WHEN** a machine uses desktop `kde`, `gnome` or `niri-noctalia`
- **THEN** audio output works through PipeWire, Bluetooth devices can be paired, and printers can be added

#### Scenario: No graphical desktop
- **WHEN** a machine uses desktop `none`
- **THEN** none of these services are enabled

### Requirement: niri-noctalia ships a central default configuration
On `niri-noctalia` machines the central repository SHALL provide a default niri configuration used by every user who has no niri configuration of their own. It MUST include keybindings to open Noctalia's application launcher, a terminal, and the lock screen. A user's own niri configuration MUST take precedence over the default.

#### Scenario: User without own configuration
- **WHEN** a user without `~/.config/niri/config.kdl` logs into niri
- **THEN** the central default configuration is used and its keybinding opens Noctalia's launcher

#### Scenario: User with own configuration
- **WHEN** a user's profile provides `~/.config/niri/config.kdl`
- **THEN** niri uses that configuration and Noctalia still starts
