## MODIFIED Requirements

### Requirement: Flatpak apps are independent of system generations
Flatpak apps SHALL stay installed and usable across system upgrades and across booting an older system generation. They are not part of the repository's configuration: a system upgrade MUST NOT install or remove Flatpak apps.

#### Scenario: Boot an older generation
- **WHEN** a user with installed Flatpak apps boots the previous system generation from the boot menu
- **THEN** the same Flatpak apps are installed and start

#### Scenario: Upgrade keeps apps
- **WHEN** a user with installed Flatpak apps runs `nixos-central upgrade`
- **THEN** the same Flatpak apps are installed afterwards
