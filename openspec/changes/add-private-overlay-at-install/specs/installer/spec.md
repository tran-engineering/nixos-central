# Spec Delta

## MODIFIED Requirements

### Requirement: Installer accepts optional flags
The installer SHALL accept `--hostname`, `--user`, `--desktop`, `--disk`, `--private`, and `--profile`, passed via `sh -s -- <flags>`. A value given as a flag MUST NOT be prompted for. Unknown flags MUST abort with a usage message before any disk is modified.

#### Scenario: All machine facts given as flags
- **WHEN** the user runs the installer with `--hostname foo --user alice --desktop kde`
- **THEN** the installer does not ask for hostname, username, or desktop

#### Scenario: Unknown flag
- **WHEN** the user passes `--colour blue`
- **THEN** the installer prints usage and exits non-zero without modifying any disk

#### Scenario: Overlay and profile given as flags
- **WHEN** the user passes `--private git+ssh://git@github.com/alice/private --profile developer`
- **THEN** the installer does not ask whether to set up an overlay, for its URL, or for the profile

#### Scenario: Profile without overlay
- **WHEN** the user passes `--profile developer` without `--private`
- **THEN** the installer explains that a profile can only be chosen together with a private overlay and exits non-zero before modifying any disk

### Requirement: Installer produces a centrally managed system
The installer SHALL generate hardware configuration for the machine, write a per-machine flake (see `host-configuration`) to `/etc/nixos` on the target, install the system from it, and print a summary (hostname, user, desktop, disk, and, if one was set up, the private overlay and profile) before rebooting on user confirmation.

#### Scenario: Successful install
- **WHEN** installation completes
- **THEN** `/etc/nixos` on the installed system contains the per-machine flake and hardware configuration, and the installer prints the summary and offers to reboot

#### Scenario: Successful install with overlay
- **WHEN** installation with the private overlay `git+ssh://git@github.com/alice/private` and profile `developer` completes
- **THEN** the summary names the overlay URL and the profile

#### Scenario: Install step fails
- **WHEN** any installation step fails
- **THEN** the installer stops, prints which step failed and the path of a log file, and does not reboot

## ADDED Requirements

### Requirement: Private overlay is offered during installation
Unless `--private` is given, the installer SHALL ask before any disk is modified whether to set up a private overlay; the default answer is no. If the user agrees, it SHALL ask for the overlay's flake URL, defaulting to the central repository's default overlay. Declining MUST produce the same installation as before this option existed.

#### Scenario: Overlay declined
- **WHEN** the user presses Enter at the private overlay question
- **THEN** no SSH key is generated, no profile is asked for, and the machine flake declares no overlay

#### Scenario: Default overlay accepted
- **WHEN** the user agrees and presses Enter at the URL question
- **THEN** the installer uses `git+ssh://git@github.com/tran-engineering/nixos-central-private` (or the default a fork configured)

### Requirement: Installer generates an SSH key for the overlay
When a private overlay is set up, the installer SHALL generate an ed25519 key pair without a passphrase for the primary user and SHALL display its public key both as text and as a QR code in the terminal, with a hint where to add it on GitHub. It SHALL then wait until the user confirms that the key was added. The private key MUST NOT be written to the Nix store.

#### Scenario: Key shown as QR code
- **WHEN** the user chooses to set up a private overlay
- **THEN** the terminal shows the public key as text and as a QR code that, when scanned with a phone, yields exactly the public key line

#### Scenario: QR code fits the console
- **WHEN** the installer runs on the 80-column console of the live image
- **THEN** the QR code is displayed without wrapping lines

### Requirement: Installer checks overlay access before installing
After the user confirms, the installer SHALL check that the overlay can be read with the generated key, using GitHub's known host key without a host-key prompt. If the check fails, it SHALL show the error and let the user retry or continue without the overlay. No disk MUST be modified before this choice is made.

#### Scenario: Key added in time
- **WHEN** the user has added the key to GitHub and confirms
- **THEN** the check succeeds and the installer continues with the profile choice

#### Scenario: Key not yet added
- **WHEN** the user confirms before the key was added
- **THEN** the installer reports that the overlay can't be read and offers to retry or to continue without the overlay

#### Scenario: Continue without overlay
- **WHEN** the check fails and the user chooses to continue without the overlay
- **THEN** the installation proceeds as if the overlay had been declined, and the generated key is still installed for the primary user

#### Scenario: Unreadable overlay given as flag
- **WHEN** `--private` names a repository the key can't read
- **THEN** the installer offers the same retry and continue choices before any disk is modified

### Requirement: Installer lets the user choose an overlay profile
After the access check succeeds, the installer SHALL list the overlay's profiles and ask for one, defaulting to the primary user's name if the overlay has a profile of that name, otherwise to `default`. A name not offered by the overlay MUST be rejected and re-prompted (interactive) or abort before any disk is modified (flag). The chosen profile SHALL be recorded in the machine flake.

#### Scenario: Generic profile for any user
- **WHEN** the overlay has profiles `default` and `developer`, the user is `alice`, and she chooses `developer`
- **THEN** the machine flake records profile `developer`, and after installation `alice` has the overlay's `developer` profile

#### Scenario: Default suggestion
- **WHEN** the overlay has a profile `kt` and the primary user is `kt`
- **THEN** the profile question suggests `kt`

#### Scenario: Unknown profile flag
- **WHEN** `--profile tester` is given and the overlay has no profile `tester`
- **THEN** the installer lists the overlay's profiles and exits non-zero before modifying any disk

### Requirement: Installed system has the overlay and the key
When an overlay was set up, the installed system SHALL be built with the overlay declared in its machine flake, in the same form that `nixos-central private setup` writes, so that `nixos-central private remove` works on it. The generated key SHALL be installed as the primary user's `~/.ssh/id_ed25519` and `~/.ssh/id_ed25519.pub`, owned by that user, with the private key readable only by them.

#### Scenario: First boot with overlay
- **WHEN** the machine installed with an overlay boots and the primary user logs in
- **THEN** the overlay's files are present, and the daily upgrade can fetch the overlay with the installed key

#### Scenario: Remove after install
- **WHEN** the primary user runs `nixos-central private remove` on a machine installed with an overlay and profile
- **THEN** the overlay and the recorded profile are removed from the machine flake and the system activates without them
