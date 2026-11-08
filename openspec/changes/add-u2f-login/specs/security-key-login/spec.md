# Spec Delta

## Purpose

Lets users of graphical nixos-central machines sign in and unlock their session by touching an enrolled U2F/FIDO2 security key instead of typing their password, without weakening or replacing password login.

## ADDED Requirements

### Requirement: Security key at the graphical login screen
On every machine with a graphical desktop, the display manager's login screen SHALL accept a touch of a security key enrolled for the user as an alternative to the user's password.

#### Scenario: KDE login with an enrolled key
- **WHEN** a user with an enrolled key selects their account on the GDM login screen of a KDE machine, with the key plugged in, and touches the key when prompted
- **THEN** the session starts without the password being typed

#### Scenario: GNOME login with an enrolled key
- **WHEN** a user with an enrolled key logs in on the GDM login screen of a GNOME machine, with the key plugged in, and touches the key when prompted
- **THEN** the session starts without the password being typed

#### Scenario: niri-noctalia login with an enrolled key
- **WHEN** a user with an enrolled key selects their account on the GDM login screen of a niri-noctalia machine, with the key plugged in, and touches the key when prompted
- **THEN** the session starts without the password being typed

### Requirement: Security key at the lock screen
On every machine with a graphical desktop, the desktop's lock screen SHALL accept a touch of a security key enrolled for the user as an alternative to the user's password.

#### Scenario: Unlock KDE with an enrolled key
- **WHEN** a KDE session is locked and its user touches their enrolled key
- **THEN** the session unlocks

#### Scenario: Unlock GNOME with an enrolled key
- **WHEN** a GNOME session is locked and its user touches their enrolled key
- **THEN** the session unlocks

#### Scenario: Unlock Noctalia with an enrolled key
- **WHEN** a niri-noctalia session is locked by Noctalia and its user touches their enrolled key
- **THEN** the session unlocks

### Requirement: Password keeps working
Wherever a security key is accepted, the user's password SHALL remain accepted. This SHALL hold whether or not the user has enrolled a key and whether or not the key is plugged in. A missing or invalid enrollment file MUST NOT prevent password login.

#### Scenario: User without an enrolled key
- **WHEN** a user who never enrolled a key logs in at the login screen with their password
- **THEN** login succeeds

#### Scenario: Enrolled user without the key at hand
- **WHEN** a user with an enrolled key has no key plugged in and types their password at the login or lock screen
- **THEN** login or unlock succeeds

### Requirement: Console login and sudo stay password-only
TTY login and `sudo` SHALL NOT accept a security key in place of the password. These entry points SHALL authenticate with the password as before this change.

#### Scenario: sudo with key plugged in
- **WHEN** a user with an enrolled key plugged in runs `sudo` in a terminal
- **THEN** sudo asks for the password and does not prompt for a key touch

#### Scenario: Console login
- **WHEN** a user with an enrolled key logs in on a TTY
- **THEN** the login asks for the password and does not accept a key touch instead

### Requirement: No security key login without a desktop
Machines with desktop `none` SHALL NOT accept a security key for any login.

#### Scenario: Headless machine
- **WHEN** a machine with desktop `none` is built
- **THEN** none of its login entry points accepts a security key

### Requirement: Per-user enrollment file
A user's enrolled keys SHALL be read from `~/.config/Yubico/u2f_keys` in that user's home directory. The tool that creates the file (`pamu2fcfg`) SHALL be available on every machine with a graphical desktop. Removing a key's entry from the file SHALL stop that key from being accepted.

#### Scenario: Enroll a key
- **WHEN** a user runs the enrollment command documented in the README and touches the key
- **THEN** the key is accepted at the login and lock screens from then on, without a rebuild

#### Scenario: Remove a lost key
- **WHEN** a user deletes a lost key's entry from `~/.config/Yubico/u2f_keys`
- **THEN** that key is no longer accepted

### Requirement: Enrollment is portable across the user's machines
Keys SHALL be enrolled for one origin shared by all nixos-central machines, not for the individual machine. An enrollment file created on one machine SHALL work unchanged on the user's other nixos-central machines.

#### Scenario: Second machine
- **WHEN** a user copies their `~/.config/Yubico/u2f_keys` from machine `foo` to the same path on machine `bar`
- **THEN** the same key is accepted at `bar`'s login and lock screens

### Requirement: Enrollment is documented
The README SHALL describe how to enroll a key, how to add a backup key, how to remove a key, and the security trade-off. The trade-off is that whoever holds an enrolled key can unlock the user's graphical session without the password.

#### Scenario: User looks for setup instructions
- **WHEN** a user reads the README to set up their YubiKey
- **THEN** they find the enrollment command, the backup-key command, removal instructions and the security note
