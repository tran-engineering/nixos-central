# VM tests for the central configuration (run with `nix flake check` or
# `nix build .#checks.x86_64-linux.<name>`).
{ inputs, system }:
let
  inherit (inputs) nixpkgs;
  pkgs = nixpkgs.legacyPackages.${system};
  inherit (nixpkgs) lib;
  central = import ../lib { inherit inputs; };

  # A machine as mkHost would build it, adapted to the test VM:
  # no installer-written password file, no binary cache.
  testHost =
    args:
    { lib, ... }:
    {
      imports = central.hostModules (
        {
          hostname = "machine";
          user = "alice";
          disk = "/dev/vda";
          stateVersion = central.release;
        }
        // args
      );
      users.users.alice = {
        hashedPasswordFile = lib.mkForce null;
        password = "test";
      };
      nix.settings.substituters = lib.mkForce [ ];
      nix.settings.flake-registry = ""; # offline VM: no global registry download
    };

  # Nodes evaluate their own nixpkgs (the base sets nixpkgs.config).
  runTest =
    test:
    lib.nixos.runTest {
      imports = [ test ];
      hostPkgs = pkgs;
      node.pkgsReadOnly = false;
      node.specialArgs = { inherit inputs; };
    };
in
{
  # nix-shell -p / nix shell nixpkgs#... resolve to the system's pinned nixpkgs, offline.
  shells = runTest {
    name = "nixos-central-shells";
    nodes.machine =
      { pkgs, ... }:
      {
        imports = [ (testHost { desktop = "none"; }) ];
        virtualisation.memorySize = 3072;
        virtualisation.additionalPaths = [
          pkgs.hello
          pkgs.stdenv
        ];
      };
    testScript = ''
      machine.wait_for_unit("multi-user.target")
      machine.succeed("nix-shell -p hello --run hello | grep 'Hello, world!'")
      machine.succeed("nix shell nixpkgs#hello -c hello | grep 'Hello, world!'")
      machine.succeed("test \"$(nix eval --raw nixpkgs#lib.version)\" = '${lib.version}'")
      machine.fail("nix-channel --list | grep .")
    '';
  };

  # A staged generation produces exactly one desktop notification per generation.
  reboot-notify = runTest {
    name = "nixos-central-reboot-notify";
    nodes.machine =
      { pkgs, ... }:
      {
        imports = [ (testHost { desktop = "kde"; }) ];
        services.displayManager.autoLogin = {
          enable = true;
          user = "alice";
        };
        virtualisation.memorySize = 4096;
        virtualisation.cores = 2;
        virtualisation.additionalPaths = [ (pkgs.writeTextDir "fake-system" "staged") ];
      };
    testScript =
      { nodes, ... }:
      let
        fake = nodes.machine.virtualisation.additionalPaths;
      in
      ''
        user = "systemctl --user -M alice@"
        unit = "nixos-central-reboot-notify"
        def notifications():
            return int(machine.succeed(f"journalctl _SYSTEMD_USER_UNIT={unit}.service | grep -c 'notified about' || true").strip())

        # Test VMs boot without a system profile; start from a regular installed state.
        machine.succeed("nix-env -p /nix/var/nix/profiles/system --set $(readlink -f /run/booted-system)")
        machine.wait_until_succeeds(f"{user} is-active graphical-session.target", timeout=900)
        machine.wait_until_succeeds(f"{user} is-active {unit}.timer")
        # notify-send needs Plasma's notification server
        machine.wait_until_succeeds("pgrep -u alice -f plasmashell", timeout=900)
        machine.sleep(30)

        with subtest("no notification without a staged update"):
            machine.succeed(f"{user} start {unit}.service")
            assert notifications() == 0

        with subtest("staged update notifies once"):
            machine.succeed("nix-env -p /nix/var/nix/profiles/system --set ${builtins.head fake}")
            machine.succeed(f"{user} start {unit}.service")
            machine.succeed(f"{user} start {unit}.service")
            assert notifications() == 1, f"expected 1 notification, got {notifications()}"

        with subtest("after reboot into the staged generation: no notification"):
            machine.succeed("nix-env -p /nix/var/nix/profiles/system --set $(readlink -f /run/booted-system)")
            machine.succeed(f"{user} start {unit}.service")
            assert notifications() == 1
      '';
  };
}
