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
The installer SHALL accept `--hostname`, `--user`, `--desktop`, `--disk`, `--keyboard-layout`, `--time-zone`, `--private`, `--profile`, `--nvidia`, and `--no-nvidia`, passed via `sh -s -- <flags>`. A value given as a flag MUST NOT be prompted for. Unknown flags MUST abort with a usage message before any disk is modified.

#### Scenario: All machine facts given as flags
- **WHEN** the user runs the installer with `--hostname foo --user alice --desktop kde --keyboard-layout sg --time-zone Europe/Zurich`
- **THEN** the installer does not ask for hostname, username, desktop, keyboard layout, or time zone

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
For each of keyboard layout, time zone, hostname, username, and desktop not given as a flag, the installer SHALL prompt the user on the terminal, even though the script itself is read from a pipe. It SHALL ask in that order, so later answers are typed with the chosen keyboard layout. Keyboard layout SHALL default to `us`; time zone SHALL default to `Europe/Zurich`; hostname SHALL default to `nixos-` plus four random characters; desktop SHALL default to `kde`.

#### Scenario: No flags given
- **WHEN** the user runs the installer without flags
- **THEN** the installer prompts for keyboard layout (default `us`), time zone (default `Europe/Zurich`), hostname (with a generated default), username, and desktop (default `kde`), reading answers from the terminal

#### Scenario: Default time zone accepted
- **WHEN** the user accepts the suggested time zone
- **THEN** the machine flake records `timeZone = "Europe/Zurich";`

### Requirement: Input values are validated
The installer MUST reject a keyboard layout or desktop not offered by the central repository, a time zone not in the live system's time zone database, a hostname that is not a valid RFC 1123 label, and a username that is not a valid lowercase POSIX login name or is reserved (e.g. `root`), and re-prompt (interactive) or abort (flag).

#### Scenario: Invalid username via prompt
- **WHEN** the user enters `Alice Smith` as username
- **THEN** the installer explains the rule and prompts again

#### Scenario: Unknown desktop via flag
- **WHEN** the user passes `--desktop windows`
- **THEN** the installer lists the available desktops and exits non-zero before modifying any disk

#### Scenario: Unknown time zone via flag
- **WHEN** the user passes `--time-zone Europe/Zürich`
- **THEN** the installer says the time zone is unknown, names `timedatectl list-timezones` to see valid names, and exits non-zero before modifying any disk

#### Scenario: Unknown time zone via plain prompt
- **WHEN** the user types `CET+1` at the plain time zone prompt
- **THEN** the installer says the time zone is unknown and prompts again

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
The installer SHALL generate hardware configuration for the machine, write a per-machine flake (see `host-configuration`) to `/etc/nixos` on the target, install the system from it, and print a summary (hostname, user, desktop, keyboard layout, time zone, disk, and, if set up, the NVIDIA driver and the private overlay and profile) before rebooting on user confirmation.

#### Scenario: Successful install
- **WHEN** installation completes
- **THEN** `/etc/nixos` on the installed system contains the per-machine flake and hardware configuration, and the installer prints the summary, including the time zone, and offers to reboot

#### Scenario: Successful install with overlay
- **WHEN** installation with the private overlay `git+ssh://git@github.com/alice/private` and profile `developer` completes
- **THEN** the summary names the overlay URL and the profile

#### Scenario: Successful install with NVIDIA
- **WHEN** installation with the NVIDIA driver completes on a hybrid laptop
- **THEN** the summary says the NVIDIA driver is installed with PRIME offload

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

### Requirement: Installer detects NVIDIA GPUs
The installer SHALL look for an NVIDIA display controller before any disk is modified. If it finds none and `--nvidia` was not passed, it MUST ask nothing about NVIDIA and record `nvidia = null`.

#### Scenario: Machine without NVIDIA GPU
- **WHEN** the installer runs on a machine with no NVIDIA display controller and without NVIDIA flags
- **THEN** it asks no NVIDIA question and the machine flake records `nvidia = null`

### Requirement: Installer confirms the NVIDIA driver
When an NVIDIA GPU is found and no NVIDIA flag was passed, the installer SHALL show the GPU and what it would record, state that the open kernel modules need a Turing or newer GPU, and ask whether to install the driver, suggesting yes. Declining MUST record `nvidia = null`.

#### Scenario: Driver accepted
- **WHEN** an NVIDIA GPU is found and the user accepts the suggestion
- **THEN** the machine flake records the detected NVIDIA facts

#### Scenario: Driver declined
- **WHEN** an NVIDIA GPU is found and the user declines
- **THEN** the machine flake records `nvidia = null`

### Requirement: Installer records PRIME only for hybrid laptops
The installer SHALL record bus IDs only when the machine has an NVIDIA GPU, an Intel or AMD integrated GPU and a system battery. Bus IDs MUST use decimal numbers, whatever their hexadecimal form in the PCI address. Batteries of peripherals MUST NOT count as a system battery. In every other case with an NVIDIA GPU, it SHALL record `nvidia = { }`.

#### Scenario: Hybrid laptop
- **WHEN** the machine has an Intel GPU at `0000:00:02.0`, an NVIDIA GPU at `0000:01:00.0` and a system battery
- **THEN** the machine flake records `intelBusId = "PCI:0@0:2:0"` and `nvidiaBusId = "PCI:1@0:0:0"`

#### Scenario: Hexadecimal PCI address
- **WHEN** a hybrid laptop's NVIDIA GPU is at `0000:0a:00.0`
- **THEN** the machine flake records `nvidiaBusId = "PCI:10@0:0:0"`

#### Scenario: AMD hybrid laptop
- **WHEN** the machine has an AMD integrated GPU, an NVIDIA GPU and a system battery
- **THEN** the machine flake records `amdgpuBusId` and `nvidiaBusId`

#### Scenario: Desktop with an enabled integrated GPU
- **WHEN** the machine has an Intel GPU and an NVIDIA GPU, and no system battery
- **THEN** the machine flake records `nvidia = { }`

#### Scenario: Desktop with a wireless mouse
- **WHEN** the machine has an Intel GPU and an NVIDIA GPU, and the only battery reported belongs to a wireless mouse
- **THEN** the machine flake records `nvidia = { }`

#### Scenario: Laptop without an integrated GPU
- **WHEN** the machine has a system battery and an NVIDIA GPU as its only display controller
- **THEN** the machine flake records `nvidia = { }`

### Requirement: NVIDIA flags answer the question
The installer SHALL accept `--nvidia` and `--no-nvidia`. `--nvidia` MUST record the detected NVIDIA facts without asking and abort before any disk is modified when no NVIDIA GPU is found. `--no-nvidia` MUST record `nvidia = null` without asking. Passing both MUST abort before any disk is modified.

#### Scenario: --nvidia on an NVIDIA machine
- **WHEN** the user passes `--nvidia` and an NVIDIA GPU is found
- **THEN** the installer asks no NVIDIA question and records the detected facts

#### Scenario: --nvidia without an NVIDIA GPU
- **WHEN** the user passes `--nvidia` and no NVIDIA GPU is found
- **THEN** the installer explains this and exits non-zero without modifying any disk

#### Scenario: --no-nvidia on an NVIDIA machine
- **WHEN** the user passes `--no-nvidia` and an NVIDIA GPU is found
- **THEN** the installer asks no NVIDIA question and the machine flake records `nvidia = null`

#### Scenario: Both flags
- **WHEN** the user passes `--nvidia --no-nvidia`
- **THEN** the installer explains the conflict and exits non-zero without modifying any disk

### Requirement: NVIDIA's download server is checked when NVIDIA is selected
When the NVIDIA driver is selected, the installer SHALL verify that `download.nvidia.com` is reachable before any disk is modified, and abort with an actionable message if not. When it is not selected, it MUST NOT contact that server.

#### Scenario: NVIDIA's server unreachable
- **WHEN** the NVIDIA driver is selected and `download.nvidia.com` cannot be reached
- **THEN** the installer aborts without modifying any disk and offers the network check or `--no-nvidia` as ways forward

#### Scenario: No NVIDIA selected
- **WHEN** the machine records `nvidia = null` and `download.nvidia.com` cannot be reached
- **THEN** the installation continues

### Requirement: Choices are menus on capable terminals
When the terminal can show menus, the installer SHALL present choices from a fixed set as menus with the default preselected: keyboard layout, desktop and overlay profile as a list, the time zone as a list filtered by typing, and yes/no questions and retry-or-skip as a selection. The installation image's start-up offers SHALL use the same yes/no selection. The disk wipe confirmation, passphrases, passwords, hostname, username and overlay URL MUST stay typed input.

#### Scenario: Pick a desktop from a menu
- **WHEN** the installer runs on the live image's first console without `--desktop`
- **THEN** it shows the offered desktops as a list with `kde` selected, and Enter chooses `kde`

#### Scenario: Find a time zone by typing
- **WHEN** the user types `lisb` in the time zone menu and presses Enter
- **THEN** the machine flake records `timeZone = "Europe/Lisbon";`

#### Scenario: Answer stays visible
- **WHEN** the user picks `Europe/Lisbon` in the time zone menu
- **THEN** the menu disappears and the line `Time zone: Europe/Lisbon` stays on the screen

#### Scenario: Wipe still needs a typed yes
- **WHEN** the installer is about to erase the disk on a terminal that can show menus
- **THEN** it still proceeds only if the user types `yes`

#### Scenario: Menu cancelled
- **WHEN** the user presses Ctrl-C in a menu, or Escape in a list, before the disk is modified
- **THEN** the installer exits non-zero without modifying any disk

#### Scenario: Escape in a yes/no question
- **WHEN** the user presses Escape at "Set up a private overlay?"
- **THEN** the installer takes it as no and continues

### Requirement: Plain prompts without a capable terminal
When the terminal cannot show menus, or the menu program cannot be obtained, the installer and the installation image SHALL ask every question as a plain line prompt with the default in brackets. The prompt texts and accepted answers SHALL be the same as without menus. Serial consoles and `TERM=dumb` count as terminals that cannot show menus.

#### Scenario: Install over a serial console
- **WHEN** the installer runs with `TERM=dumb`
- **THEN** it asks `Desktop [kde]: ` as a line prompt and accepts a typed desktop name

#### Scenario: Menu program unavailable
- **WHEN** the menu program can't be fetched on a live image that doesn't include it
- **THEN** the installer continues with plain prompts instead of failing
