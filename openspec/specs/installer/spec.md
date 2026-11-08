# installer Specification

## Purpose

Lets anyone who has booted a NixOS live image install a complete, centrally managed NixOS system with a single `curl | sh` command and minimal interaction.

## Requirements

### Requirement: Installer is published at a stable URL
The installer script SHALL be served from `https://tran-engineering.github.io/nixos-central` and SHALL be runnable as `curl -sL https://tran-engineering.github.io/nixos-central | sh`. The published script MUST be the version from the central repository's default branch.

#### Scenario: One-line install
- **WHEN** a user on a booted NixOS live image runs `curl -sL https://tran-engineering.github.io/nixos-central | sh`
- **THEN** the installer starts and begins interactive setup

#### Scenario: Script update is published
- **WHEN** a change to the installer is merged to the default branch
- **THEN** the URL serves the updated script after publication completes

### Requirement: Truncated downloads do not execute partially
The installer MUST perform no action unless the complete script has been received.

#### Scenario: Connection drops mid-download
- **WHEN** the download is interrupted before the end of the script
- **THEN** no disk is modified and no installation step runs

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

### Requirement: Missing values are prompted interactively
For each of hostname, username, and desktop not given as a flag, the installer SHALL prompt the user on the terminal, even though the script itself is read from a pipe. Hostname SHALL default to `nixos-` plus four random characters; desktop SHALL default to `kde`.

#### Scenario: No flags given
- **WHEN** the user runs the installer without flags
- **THEN** the installer prompts for hostname (with a generated default), username, and desktop (with default `kde`), reading answers from the terminal

### Requirement: Input values are validated
The installer MUST reject a hostname that is not a valid RFC 1123 label, a username that is not a valid lowercase POSIX login name or is reserved (e.g. `root`), and a desktop not offered by the central repository, and re-prompt (interactive) or abort (flag).

#### Scenario: Invalid username via prompt
- **WHEN** the user enters `Alice Smith` as username
- **THEN** the installer explains the rule and prompts again

#### Scenario: Unknown desktop via flag
- **WHEN** the user passes `--desktop windows`
- **THEN** the installer lists the available desktops and exits non-zero before modifying any disk

### Requirement: Preflight checks fail early
Before any prompt that leads to disk changes, the installer SHALL verify it runs on a NixOS live image, booted in UEFI mode, with network access to GitHub, and SHALL obtain root privileges (via sudo if needed). Any failed check MUST abort with an actionable message.

#### Scenario: Legacy BIOS boot
- **WHEN** the machine was booted in legacy BIOS mode
- **THEN** the installer aborts and tells the user to boot the USB image in UEFI mode

#### Scenario: No network
- **WHEN** GitHub is not reachable
- **THEN** the installer aborts and suggests connecting to the network (e.g. with `nmtui`)

#### Scenario: Not a live image
- **WHEN** the installer is run on an installed Linux system that is not NixOS
- **THEN** it aborts before asking for root privileges, and the message includes the one-line command for the home installer

#### Scenario: Installed NixOS
- **WHEN** the installer is run on an installed NixOS machine
- **THEN** it aborts before asking for root privileges and tells the user to boot the NixOS installation image

### Requirement: Target disk is selected automatically
Without `--disk`, the installer SHALL select the first whole disk of at least 40 GiB that is neither the device the live image booted from nor a removable/USB device. If none qualifies, it MUST abort and list the available disks.

#### Scenario: USB stick enumerates first
- **WHEN** the live USB is `/dev/sda` and an internal 512 GB NVMe drive is `/dev/nvme0n1`
- **THEN** the installer selects `/dev/nvme0n1`

#### Scenario: No suitable disk
- **WHEN** the only internal disk is 32 GiB
- **THEN** the installer aborts and prints the list of disks with sizes

#### Scenario: Disk given explicitly
- **WHEN** the user passes `--disk /dev/sdb`
- **THEN** the installer uses `/dev/sdb` without auto-detection, still subject to wipe confirmation

### Requirement: Disk wipe requires typed confirmation
Before modifying the target disk, the installer SHALL display the device path, size, and model, state that all data on it will be erased, and proceed only if the user types `yes`. Any other input MUST abort without changes.

#### Scenario: User confirms
- **WHEN** the installer shows `/dev/nvme0n1 (476 GiB, Samsung SSD 980)` and the user types `yes`
- **THEN** installation proceeds

#### Scenario: User declines
- **WHEN** the user types `y` or presses Enter
- **THEN** the installer exits without modifying any disk

### Requirement: Disk is encrypted with a prompted passphrase
The installer SHALL prompt for a LUKS passphrase twice (hidden input), re-prompting on mismatch or empty input, and SHALL set up the disk as EFI system partition plus a LUKS-encrypted root. The encrypted root SHALL hold a single ext4 filesystem mounted at `/`, with no separate filesystems for `/home` or `/nix`. The passphrase MUST NOT be written to the installed system or the Nix store.

#### Scenario: Passphrase mismatch
- **WHEN** the two passphrase entries differ
- **THEN** the installer reports the mismatch and prompts again

#### Scenario: Boot after install
- **WHEN** the installed system boots
- **THEN** it asks for the LUKS passphrase before mounting the root filesystem

#### Scenario: Root filesystem layout
- **WHEN** the installed system is running
- **THEN** `/` is an ext4 filesystem on the unlocked LUKS device, and `/home` and `/nix` are on that same filesystem

### Requirement: User password is set during install
The installer SHALL offer to reuse the LUKS passphrase as the user's login password; if declined, it SHALL prompt for a separate password twice. Only a password hash MUST be stored on the installed system, outside the Nix store.

#### Scenario: Reuse disk passphrase
- **WHEN** the user accepts reusing the disk passphrase
- **THEN** the primary user can log in with the same passphrase after installation

#### Scenario: Separate password
- **WHEN** the user declines and enters a separate password
- **THEN** the primary user logs in with that password

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
