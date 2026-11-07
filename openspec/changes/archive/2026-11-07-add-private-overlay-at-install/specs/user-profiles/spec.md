# Spec Delta

## ADDED Requirements

### Requirement: NixOS machines can record a profile
A NixOS machine flake SHALL be able to record a profile name. If one is recorded, it SHALL be used in place of the primary user's name to choose the central profile and the overlay profile, with the same fallback to the shared default profile. Without a recorded profile, the primary user's name SHALL be used as before. The account name MUST stay the primary user's name either way.

#### Scenario: Profile that exists only in the overlay
- **WHEN** machine `foo` has primary user `alice`, records profile `developer`, the central repository has no profile `developer`, and the overlay has one
- **THEN** `alice`'s environment is built from the shared default profile plus the overlay's `developer` profile, and her login name and home directory stay `alice`

#### Scenario: Recorded profile exists in the central repository
- **WHEN** machine `foo` records profile `kt` and the central repository has a profile `kt`
- **THEN** the primary user's environment is built from the central `kt` profile

#### Scenario: No recorded profile
- **WHEN** a machine flake records no profile
- **THEN** the profile is chosen by the primary user's name exactly as before
