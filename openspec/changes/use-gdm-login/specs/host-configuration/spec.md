# Spec Delta

## MODIFIED Requirements

### Requirement: Desktop is selectable per machine
The central repository SHALL offer a set of named desktops, including `kde`, `gnome`, `niri-noctalia` and `none`. The machine flake's desktop value SHALL determine which desktop environment is enabled. An unknown desktop name MUST fail evaluation with a message listing valid names.

#### Scenario: KDE selected
- **WHEN** a machine flake sets desktop `kde`
- **THEN** the system boots into the graphical GDM login, and logging in starts a KDE Plasma Wayland session

#### Scenario: GNOME selected
- **WHEN** a machine flake sets desktop `gnome`
- **THEN** the system boots into the graphical GDM login, and logging in starts a GNOME Wayland session

#### Scenario: niri with Noctalia selected
- **WHEN** a machine flake sets desktop `niri-noctalia`
- **THEN** the system boots into the graphical GDM login, and logging in starts a niri session in which the Noctalia shell is running

#### Scenario: Change desktop later
- **WHEN** a user changes the desktop value in `/etc/nixos/flake.nix` to another offered desktop and rebuilds
- **THEN** the new desktop is active after rebuild

#### Scenario: Invalid desktop
- **WHEN** a machine flake sets desktop `foo`
- **THEN** evaluation fails and lists the valid desktop names
