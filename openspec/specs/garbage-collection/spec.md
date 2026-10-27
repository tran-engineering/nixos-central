# garbage-collection Specification

## Purpose

Keeps the Nix store of every machine and standalone home from growing without bound, by removing old generations and unreferenced store paths automatically while keeping recent rollback targets.

## Requirements

### Requirement: Weekly system garbage collection
Each NixOS machine SHALL, once a week, delete system generations older than 30 days and then remove store paths that nothing references any more. A run missed while the machine was off MUST run soon after it is next booted.

#### Scenario: Old system generations
- **WHEN** the machine has system generations from 45, 35, 20 and 2 days ago, the one from 2 days ago is current, and the weekly collection runs
- **THEN** the generation from 45 days ago is deleted and its store paths that nothing else references are removed

#### Scenario: Machine was off
- **WHEN** a laptop was powered off at the scheduled time
- **THEN** the collection runs shortly after the laptop is next booted

### Requirement: Weekly home garbage collection
Every home, on NixOS machines and standalone homes, SHALL once a week delete the user's own profile generations older than 30 days (home-manager on standalone homes, and the user's personal profile from `nix profile` or `nix-env`) and then remove unreferenced store paths. A run missed MUST run soon after the user is next logged in. It MUST NOT need root.

#### Scenario: Standalone home
- **WHEN** a standalone home has home-manager generations from 60, 40 and 3 days ago, the latest is active, and the weekly collection runs
- **THEN** the generation from 60 days ago is deleted, without asking for a password

#### Scenario: Home on a NixOS machine
- **WHEN** the primary user of a NixOS machine has personal profile generations (from `nix profile install`) older than 30 days
- **THEN** the weekly home collection deletes them, although the system collection does not

### Requirement: Rollback targets are kept
Collection MUST NOT delete the current generation, any generation from the last 30 days, or the generation that was current 30 days ago. Collection MUST NOT delete a generation the system is booted into or currently running.

#### Scenario: No update for months
- **WHEN** a machine was last updated 90 days ago, so the current generation is 90 days old and the previous one 120 days old, and the collection runs
- **THEN** both the current and the previous generation remain, and the previous one stays selectable in the boot menu

#### Scenario: Staged update
- **WHEN** an update is staged for the next boot and the running system's generation is 40 days old
- **THEN** the running system's generation is not deleted

### Requirement: Independent of updates
Garbage collection SHALL run on its own schedule, whether or not updates succeed.

#### Scenario: Updates failing
- **WHEN** the daily update has failed for two weeks
- **THEN** the weekly collection still runs

### Requirement: Free space kept during builds
On NixOS machines, when free space in the store drops below a lower limit during a build, unreferenced store paths SHALL be removed until free space reaches an upper limit. This MUST NOT delete generations.

#### Scenario: Disk nearly full during an update
- **WHEN** an update builds while less than the lower limit is free and unreferenced store paths exist
- **THEN** those paths are removed and the build continues

### Requirement: Retention can be changed
The retention period and schedule SHALL be defaults: a profile can change them for its home, and a machine's own modules can change them for the system, including turning collection off.

#### Scenario: Profile keeps more history
- **WHEN** profile `kt` sets the home collection to keep 90 days
- **THEN** `kt`'s home generations from the last 90 days are kept, and the build succeeds
