# Spec Delta

## Purpose

Shows users what a long build is doing (what is downloaded or built, how much is done, and how long it has taken) when they install a machine or a home, or upgrade one on demand. Unattended and non-interactive runs keep plain output.

## ADDED Requirements

### Requirement: Live build progress for user-started builds
When the NixOS installer installs the system, the home installer first activates the home, or `nixos-central upgrade` (with or without `--private`, on NixOS or a standalone home) builds the configuration, they SHALL show a live display on the terminal while the build runs. The display MUST show which items are being downloaded and built, how many are done out of the total, and the elapsed time.

#### Scenario: Installing NixOS on the console
- **WHEN** the installer reaches the installation step on the installation image's first console
- **THEN** the terminal shows a live display of the downloads and builds with their progress until the system is built

#### Scenario: Upgrading a NixOS machine
- **WHEN** a user runs `nixos-central upgrade` in a desktop terminal and the central repository has new commits
- **THEN** a live display of the downloads and builds is shown while the new configuration is built, and then the command activates it as before

#### Scenario: Upgrading only the overlay
- **WHEN** a user runs `nixos-central upgrade --private` in a terminal
- **THEN** the build is shown with the same live display

#### Scenario: Upgrading a standalone home
- **WHEN** a user runs `nixos-central upgrade` on a standalone home in a terminal
- **THEN** the build is shown with the same live display

#### Scenario: First activation by the home installer
- **WHEN** the home installer builds and activates the home on a terminal
- **THEN** the build is shown with the same live display

### Requirement: Plain build output where the display cannot work
When the output is not a terminal, the terminal type is `dumb` or `unknown`, or `NIXOS_CENTRAL_PLAIN` is set, these commands SHALL print the build's normal log lines instead of the live display, with no cursor movement or screen redraws. The installer SHALL also use plain output when the display program cannot be obtained, and say so once.

#### Scenario: Serial console
- **WHEN** the installer runs on a serial console with `TERM=dumb`
- **THEN** the installation prints the build's normal log lines and contains no screen-redraw sequences

#### Scenario: Output redirected
- **WHEN** a user runs `nixos-central upgrade > upgrade.log 2>&1`
- **THEN** `upgrade.log` contains the build's normal log lines

#### Scenario: Display program unavailable during installation
- **WHEN** the installer cannot fetch the display program
- **THEN** it prints one line saying that build progress is shown as plain output, and the installation continues

### Requirement: Display does not change outcomes
Using the live display or plain output MUST NOT change what these commands install or activate, their exit status, their messages on failure, or what they leave unchanged on failure. A build that fails while the display is shown MUST make the command fail. The build's error output MUST remain visible on the terminal.

#### Scenario: Build fails during upgrade
- **WHEN** the configuration fails to build during `nixos-central upgrade` with the live display shown
- **THEN** the command exits with an error, the failing build's error is visible, and the running system, the default boot entry and `/etc/nixos/flake.lock` are unchanged

#### Scenario: Build fails during installation
- **WHEN** the system fails to build during installation with the live display shown
- **THEN** the installer reports the failed step and the log file, as without the display, and does not reboot

### Requirement: Complete installation log
The installer's log file SHALL contain the complete build log, including any build error, whichever output is shown on the terminal. It MUST NOT contain the live display's screen redraws. While the live display is shown, the build log MAY be in Nix's machine-readable JSON-lines format.

#### Scenario: Install with live display
- **WHEN** an installation on the console showed the live display
- **THEN** `/tmp/nixos-central-install.log` contains the build's log messages, including any build error, and no screen-redraw sequences

### Requirement: Automatic upgrades unchanged
The daily automatic upgrades of NixOS machines and standalone homes MUST NOT use the live display. Their journal output SHALL stay as it is.

#### Scenario: Daily upgrade
- **WHEN** the daily automatic upgrade runs
- **THEN** its journal shows the build's normal log lines
