# Spec Delta

## Purpose

Lets anyone who has booted a NixOS live image install a complete, centrally managed NixOS system with a single `curl | sh` command and minimal interaction.

## ADDED Requirements

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
The installer SHALL accept `--hostname`, `--user`, `--desktop`, and `--disk`, passed via `sh -s -- <flags>`. A value given as a flag MUST NOT be prompted for. Unknown flags MUST abort with a usage message before any disk is modified.

#### Scenario: All machine facts given as flags
- **WHEN** the user runs the installer with `--hostname foo --user alice --desktop kde`
- **THEN** the installer does not ask for hostname, username, or desktop

#### Scenario: Unknown flag
- **WHEN** the user passes `--colour blue`
- **THEN** the installer prints usage and exits non-zero without modifying any disk

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
The installer SHALL prompt for a LUKS passphrase twice (hidden input), re-prompting on mismatch or empty input, and SHALL set up the disk as EFI system partition plus a LUKS-encrypted root. The passphrase MUST NOT be written to the installed system or the Nix store.

#### Scenario: Passphrase mismatch
- **WHEN** the two passphrase entries differ
- **THEN** the installer reports the mismatch and prompts again

#### Scenario: Boot after install
- **WHEN** the installed system boots
- **THEN** it asks for the LUKS passphrase before mounting the root filesystem

### Requirement: User password is set during install
The installer SHALL offer to reuse the LUKS passphrase as the user's login password; if declined, it SHALL prompt for a separate password twice. Only a password hash MUST be stored on the installed system, outside the Nix store.

#### Scenario: Reuse disk passphrase
- **WHEN** the user accepts reusing the disk passphrase
- **THEN** the primary user can log in with the same passphrase after installation

#### Scenario: Separate password
- **WHEN** the user declines and enters a separate password
- **THEN** the primary user logs in with that password

### Requirement: Installer produces a centrally managed system
The installer SHALL generate hardware configuration for the machine, write a per-machine flake (see `host-configuration`) to `/etc/nixos` on the target, install the system from it, and print a summary (hostname, user, desktop, disk) before rebooting on user confirmation.

#### Scenario: Successful install
- **WHEN** installation completes
- **THEN** `/etc/nixos` on the installed system contains the per-machine flake and hardware configuration, and the installer prints the summary and offers to reboot

#### Scenario: Install step fails
- **WHEN** any installation step fails
- **THEN** the installer stops, prints which step failed and the path of a log file, and does not reboot
