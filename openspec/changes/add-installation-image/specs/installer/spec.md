# Spec Delta

## ADDED Requirements

### Requirement: Installation image is published
The central repository SHALL publish a bootable x86_64 UEFI installation image as a GitHub release asset, together with its SHA-256 checksum, under a download URL that always points to the latest image. The image MUST contain no secrets.

#### Scenario: Download the latest image
- **WHEN** a user opens the documented "latest image" URL
- **THEN** they download the most recently published image and can verify it against the published checksum

#### Scenario: New NixOS release
- **WHEN** the central repository moves to a newer NixOS release
- **THEN** an image based on that release is published

### Requirement: Installation image starts the installer
After booting the installation image, the first console SHALL offer to start the installer. Declining MUST leave the user at a shell of the live system. If GitHub is not reachable, the image SHALL offer to connect to a network (e.g. with `nmtui`) and then check again.

#### Scenario: Boot and install
- **WHEN** a user boots the image on a machine with a network cable and accepts the offer
- **THEN** the installer starts without the user typing a command

#### Scenario: Wi-Fi only
- **WHEN** the image boots without network access
- **THEN** the user is offered the network setup, and after connecting, the installer starts

#### Scenario: Decline
- **WHEN** the user declines the offer
- **THEN** a shell of the live system is available and nothing is installed

### Requirement: Installation image runs the current installer
The installation image SHALL run the installer from the central repository's default branch at the time of installation, not a copy fixed when the image was built.

#### Scenario: Installer changed after the image was built
- **WHEN** the installer was changed on the default branch after the image was published
- **THEN** booting that image runs the changed installer

### Requirement: Installation image is tested end to end
The end-to-end installer test SHALL boot the same image definition that is published, with only test-specific additions such as a serial console.

#### Scenario: Image breaks the installer
- **WHEN** a change to the image definition prevents the installer from starting
- **THEN** the end-to-end test fails
