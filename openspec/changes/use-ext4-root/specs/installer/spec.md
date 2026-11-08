# Spec Delta

## MODIFIED Requirements

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
