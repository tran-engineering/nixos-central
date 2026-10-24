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
  # A staged generation produces exactly one desktop notification per
  # generation, on the given graphical desktop. `node` and `extraScript` add
  # desktop-specific configuration and checks.
  rebootNotify =
    {
      desktop,
      node ? { },
      extraScript ? "",
    }:
    runTest {
      name = "nixos-central-reboot-notify-${desktop}";
      nodes.machine =
        { pkgs, ... }:
        {
          imports = [
            (testHost { inherit desktop; })
            node
          ];
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
          # notify-send needs the desktop's notification server on alice's session bus
          machine.wait_until_succeeds(
              "busctl --user -M alice@ call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus"
              " NameHasOwner s org.freedesktop.Notifications | grep -qx 'b true'",
              timeout=900,
          )
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

          ${extraScript}
        '';
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

  # nixos-central-upgrade changes nothing when it fails or an auto-upgrade runs.
  upgrade-failures = runTest {
    name = "nixos-central-upgrade-failures";
    nodes.machine =
      { lib, pkgs, ... }:
      {
        imports = [ (testHost { desktop = "none"; }) ];
        virtualisation.memorySize = 2048;
        environment.systemPackages = [ pkgs.git ];
        # Stands in for a long-running automatic upgrade.
        systemd.services.nixos-upgrade.script = lib.mkForce "sleep infinity";
      };
    testScript = ''
      git = "git -c user.name=t -c user.email=t@t -C /tmp/central"
      def state():
          return machine.succeed("md5sum /etc/nixos/flake.lock; readlink /nix/var/nix/profiles/system")

      machine.wait_for_unit("multi-user.target")
      # The persistent timer may already have started the stand-in at boot.
      machine.succeed("systemctl stop nixos-upgrade.timer nixos-upgrade.service")
      # Test VMs boot without a system profile; start from a regular installed state.
      machine.succeed("nix-env -p /nix/var/nix/profiles/system --set $(readlink -f /run/booted-system)")

      # A machine flake whose central input is a local repo with a broken mkHost.
      machine.succeed(
          "mkdir -p /tmp/central /etc/nixos",
          "echo '{ outputs = _: { lib.mkHost = _: throw \"broken central\"; }; }' > /tmp/central/flake.nix",
          f"{git} init -q && {git} add . && {git} commit -qm one",
          "echo '{ inputs.central.url = \"git+file:///tmp/central\"; outputs = { central, ... }: { nixosConfigurations.machine = central.lib.mkHost { }; }; }' > /etc/nixos/flake.nix",
          "nix flake lock /etc/nixos",
      )

      with subtest("build failure after a central update leaves lock and profile unchanged"):
          machine.succeed(f"echo '# two' >> /tmp/central/flake.nix && {git} commit -qam two")
          before = state()
          out = machine.fail("nixos-central-upgrade 2>&1")
          # nix wrote the bumped lock before failing; the command must have restored it.
          assert "Updated input 'central'" in out, out
          assert "broken central" in out and "nothing was changed" in out, out
          assert state() == before, f"{before} != {state()}"

      with subtest("refuses while the automatic upgrade runs"):
          machine.succeed("systemctl start --no-block nixos-upgrade.service")
          machine.wait_until_succeeds("systemctl show -P ActiveState nixos-upgrade.service | grep -qx activating", timeout=30)
          before = state()
          out = machine.fail("nixos-central-upgrade 2>&1")
          assert "automatic upgrade is running" in out, out
          assert state() == before
          machine.succeed("systemctl stop nixos-upgrade.service")
    '';
  };

  reboot-notify-kde = rebootNotify { desktop = "kde"; };
  reboot-notify-gnome = rebootNotify { desktop = "gnome"; };
}
