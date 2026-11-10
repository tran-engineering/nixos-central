## MODIFIED Requirements

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

## ADDED Requirements

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
