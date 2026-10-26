# Spec Delta

## Purpose

Defines shared, opt-in building blocks of a user environment in the central repository: profiles include them instead of copying packages and settings, on NixOS machines and standalone homes alike.

## ADDED Requirements

### Requirement: Shared modules are opt-in per profile
The central repository SHALL provide shared home modules that a profile includes explicitly. A shared module MUST NOT take effect for any profile that does not include it, including the shared default profile.

#### Scenario: Profile includes a module
- **WHEN** profile `kt` includes the `dev-cli` module
- **THEN** after the next update `kt`'s environment has the tools and settings of `dev-cli`

#### Scenario: Profile without the module
- **WHEN** a user gets the shared default profile
- **THEN** none of the tools or settings of the shared modules are part of their environment

### Requirement: Shared modules are not profiles
Shared modules SHALL NOT be offered or resolved as profiles. Adding a shared module MUST NOT change the list of selectable profiles.

#### Scenario: Selectable profiles after adding a module
- **WHEN** the repository contains the shared modules and the profiles `_default` and `kt`
- **THEN** the selectable profiles are `_default` and `kt` only

#### Scenario: Login name equals a module name
- **WHEN** a machine is installed with user `dev-cli` and no `dev-cli` profile exists
- **THEN** that user gets the shared default profile, not the `dev-cli` module

### Requirement: Shared modules work on NixOS and standalone
Every shared module SHALL build as part of a profile on a NixOS machine and in a standalone home on `x86_64-linux`, and SHALL evaluate in a standalone home on `aarch64-linux`.

#### Scenario: Same module on both
- **WHEN** profile `kt` includes all shared modules and is used by NixOS machine `foo` and a standalone home on Ubuntu
- **THEN** both build, and both contain the tools and settings of the included modules

#### Scenario: ARM standalone home
- **WHEN** a standalone home on `aarch64-linux` uses profile `kt`
- **THEN** its configuration evaluates without errors

### Requirement: Module defaults can be overridden
Settings that a shared module makes about how a tool behaves (as opposed to which tools are installed) SHALL be defaults that the including profile can override by setting the same option, without forcing.

#### Scenario: Profile changes a workflow default
- **WHEN** profile `kt` includes `git` and sets git's pull behavior to merge instead of rebase
- **THEN** `kt`'s git configuration uses merge, and the build succeeds

### Requirement: Shared modules carry no personal identity
Shared modules MUST NOT set personal data such as names, email addresses, keys, or account-specific paths. These belong in the profile.

#### Scenario: Module included without identity
- **WHEN** a profile includes `git` and `jj` without setting a user name
- **THEN** the build succeeds and no name or email from another person is configured

### Requirement: General tools module
The `general-tools` module SHALL provide everyday command-line utilities that are not specific to software development: downloading, archives, disk usage, file and media inspection and conversion, network lookups, and an improved `ls`.

#### Scenario: Utilities available
- **WHEN** a profile includes `general-tools`
- **THEN** commands such as `bat`, `eza`, `dust`, `ncdu`, `7z`, `yt-dlp` and `ffmpeg` are available to the user

### Requirement: Developer CLI module
The `dev-cli` module SHALL provide command-line development tooling: search and task tools, data and secret tools, a git TUI, language toolchains, AI coding agents, infrastructure and cloud tools, and Nix tooling. git and jj are not part of it.

#### Scenario: Tooling available
- **WHEN** a profile includes `dev-cli`
- **THEN** commands such as `rg`, `just`, `jq`, `gh`, `lazygit`, `uv`, `rustup`, `claude`, `kubectl`, `tofu`, `aws` and `nixd` are available to the user

### Requirement: Developer CLI environment
The `dev-cli` module SHALL put user-installed cargo and pnpm binaries on the PATH and provide a global Node.js through mise.

#### Scenario: Language tool binaries on PATH
- **WHEN** a user of a profile with `dev-cli` installs a binary with `cargo install`
- **THEN** it can be run by name in a new login shell

#### Scenario: Node.js available
- **WHEN** a user of a profile with `dev-cli` opens a new shell
- **THEN** `node` runs the Node.js major version configured by the module

### Requirement: git module
The `git` module SHALL provide git with Git LFS and these defaults: rebase on pull with automatic stashing, and push without manual upstream setup.

#### Scenario: First push of a new branch
- **WHEN** a user of a profile with `git` runs `git push` on a new local branch
- **THEN** the branch is pushed and set to track the remote branch without extra flags

### Requirement: jj module
The `jj` module SHALL provide jj and the jjui TUI with these defaults: bookmarks on `origin` are tracked automatically, commits described `wip:` or `private:` cannot be pushed, and new files up to 10 MiB are snapshotted.

#### Scenario: Scratch commit not pushed
- **WHEN** a user of a profile with `jj` tries to `jj git push` a commit described `wip: try`
- **THEN** jj refuses to push it

### Requirement: Developer desktop module
The `dev-desktop` module SHALL provide the Zed editor with its Claude agent bridge. Zed MUST appear in the desktop's application launcher.

#### Scenario: Zed from the launcher
- **WHEN** a user of a profile with `dev-desktop` opens the application launcher on a graphical desktop
- **THEN** Zed is listed and starts, also available as `zed` in a shell

### Requirement: Single-application modules
The central repository SHALL provide one module each for IntelliJ IDEA (`idea`), Godot (`godot`) and draw.io (`drawio`). Each application MUST appear in the desktop's application launcher.

#### Scenario: Only one application included
- **WHEN** a profile includes `godot` but neither `idea` nor `drawio`
- **THEN** Godot is in the user's application launcher, and IntelliJ IDEA and draw.io are not installed

### Requirement: fish module
The `fish` module SHALL provide fish with the tide prompt, fuzzy search (fzf), directory jumping (z) and a command to jump to the repository root. The prompt MUST work without configuration in the profile; its look SHALL be a default the profile can replace.

#### Scenario: Prompt works out of the box
- **WHEN** a user of a profile with `fish` opens fish for the first time
- **THEN** the tide prompt is shown with its icons, without running `tide configure`

#### Scenario: Profile replaces the prompt
- **WHEN** a profile with `fish` provides its own tide configuration
- **THEN** fish uses the profile's prompt configuration instead of the module's

### Requirement: zsh module
The `zsh` module SHALL provide zsh with completion, autosuggestions, syntax highlighting and a shared, deduplicated history.

#### Scenario: Suggestions while typing
- **WHEN** a user of a profile with `zsh` types the start of a command they ran before
- **THEN** zsh suggests the rest of it from history

### Requirement: Terminal emulator modules
The central repository SHALL provide a `foot` and a `ghostty` module, each installing the terminal with readable defaults the profile can override. The terminals MUST appear in the desktop's application launcher and work on standalone homes after the one-time GPU setup.

#### Scenario: Override a terminal default
- **WHEN** a profile with `ghostty` sets its own font size
- **THEN** ghostty uses the profile's font size and the module's other defaults

### Requirement: Icon font for prompts
Modules whose defaults use icon glyphs (the fish prompt, the terminals) SHALL install a font that provides those glyphs, so that they render without the user installing fonts.

#### Scenario: Icons in foot
- **WHEN** a user of a profile with `fish` and `foot` opens foot
- **THEN** the prompt's icons render as glyphs, not as placeholder boxes
