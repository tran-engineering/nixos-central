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
      # The VM's store has less than min-free available; automatic collection
      # during builds would delete paths the tests add (additionalPaths) and
      # cannot rebuild offline.
      nix.settings.min-free = lib.mkForce 0;
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
        # Stands in for a long-running automatic upgrade. Without network-online:
        # the VM's second interface never comes up, so the start job would wait
        # for NetworkManager-wait-online longer than the test does.
        systemd.services.nixos-upgrade = {
          script = lib.mkForce "sleep infinity";
          wants = lib.mkForce [ ];
          after = lib.mkForce [ ];
        };
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

      with subtest("--private without an overlay changes nothing"):
          before = state()
          out = machine.fail("nixos-central-upgrade --private 2>&1")
          assert "no private overlay" in out, out
          assert state() == before
    '';
  };

  # Upgrades of a machine with a private overlay: they update the overlay too,
  # and an unreachable overlay stops them without changing anything.
  overlay-upgrades = runTest {
    name = "nixos-central-overlay-upgrades";
    nodes.machine =
      { pkgs, ... }:
      {
        imports = [
          (testHost {
            desktop = "none";
            private = (import ./overlay/flake.nix).outputs { } // {
              inputs = { };
            };
          })
        ];
        virtualisation.memorySize = 2048;
        environment.systemPackages = [ pkgs.git ];
      };
    testScript = ''
      git = "git -c user.name=t -c user.email=t@t -C"
      def state():
          return machine.succeed("md5sum /etc/nixos/flake.lock; readlink /nix/var/nix/profiles/system")

      machine.wait_for_unit("multi-user.target")
      machine.succeed("systemctl stop nixos-upgrade.timer nixos-upgrade.service")
      machine.succeed("nix-env -p /nix/var/nix/profiles/system --set $(readlink -f /run/booted-system)")

      # Stub central: reads the overlay (forcing its fetch), then fails instead of building.
      machine.succeed(
          "mkdir -p /tmp/central /tmp/private /etc/nixos",
          "echo '{ outputs = _: { lib.mkHost = a: throw \"stub central one, overlay ''${a.private.rev}\"; }; }' > /tmp/central/flake.nix",
          "echo '{ outputs = _: { homeModules.default = { }; }; }' > /tmp/private/flake.nix",
          f"{git} /tmp/central init -q && {git} /tmp/central add . && {git} /tmp/central commit -qm one",
          f"{git} /tmp/private init -q && {git} /tmp/private add . && {git} /tmp/private commit -qm one",
          "echo '{ inputs.central.url = \"git+file:///tmp/central\"; inputs.private.url = \"git+file:///tmp/private\"; outputs = { central, private, ... }: { nixosConfigurations.machine = central.lib.mkHost { inherit private; }; }; }' > /etc/nixos/flake.nix",
          "nix flake lock /etc/nixos",
      )

      with subtest("a new overlay commit is picked up"):
          machine.succeed(f"echo '# two' >> /tmp/private/flake.nix && {git} /tmp/private commit -qam two")
          new_rev = machine.succeed(f"{git} /tmp/private rev-parse HEAD").strip()
          before = state()
          out = machine.fail("nixos-central-upgrade 2>&1")
          assert "Updated input 'private'" in out and f"overlay {new_rev}" in out, out
          assert state() == before, f"{before} != {state()}"

      with subtest("--private updates only the overlay"):
          machine.succeed(f"sed -i s/one/two/ /tmp/central/flake.nix && {git} /tmp/central commit -qam two")
          machine.succeed(f"echo '# three' >> /tmp/private/flake.nix && {git} /tmp/private commit -qam three")
          new_rev = machine.succeed(f"{git} /tmp/private rev-parse HEAD").strip()
          before = state()
          out = machine.fail("nixos-central-upgrade --private 2>&1")
          assert "Updated input 'private'" in out and "Updated input 'central'" not in out, out
          # central stays at the locked revision ("one"), the overlay is the new one.
          assert f"stub central one, overlay {new_rev}" in out and "nothing was changed" in out, out
          assert state() == before, f"{before} != {state()}"

      with subtest("an unreachable overlay stops both upgrade paths"):
          machine.succeed("mv /tmp/private /tmp/private-gone")
          before = state()
          out = machine.fail("nixos-central-upgrade 2>&1")
          assert "/tmp/private" in out and "nothing was changed" in out, out
          assert state() == before, f"{before} != {state()}"
          machine.fail("systemctl start nixos-upgrade.service")
          assert "/tmp/private" in machine.succeed("journalctl -u nixos-upgrade.service")
          assert state() == before, f"{before} != {state()}"

      with subtest("root uses the primary user's key for GitHub"):
          out = machine.succeed("ssh -G github.com")
          assert "identityfile /home/alice/.ssh/id_ed25519" in out and "identitiesonly yes" in out, out
          out = machine.succeed("su - alice -c 'ssh -G github.com'")
          assert "identitiesonly no" in out, out
    '';
  };

  # nixos-central-upgrade of standalone homes changes nothing when it fails, an
  # automatic upgrade runs or its arguments are wrong; --private updates only
  # the overlay. Runs in a NixOS VM (offline: a stub central can't build a home),
  # with the home commands under other names so they don't clash with NixOS's.
  home-upgrade-failures =
    let
      homeCommand =
        private:
        lib.findFirst (p: (p.name or "") == "nixos-central-upgrade") (throw "no nixos-central-upgrade")
          (central.mkHome {
            user = "alice";
            homeDirectory = "/home/alice";
            stateVersion = central.release;
            inherit system private;
          }).config.home.packages;
      commands = pkgs.runCommand "home-upgrade-commands" { } ''
        mkdir -p $out/bin
        ln -s ${homeCommand null}/bin/nixos-central-upgrade $out/bin/home-upgrade
        ln -s ${
          homeCommand {
            inputs = { };
            homeModules.default = { };
          }
        }/bin/nixos-central-upgrade $out/bin/home-upgrade-overlay
      '';
    in
    runTest {
      name = "nixos-central-home-upgrade-failures";
      nodes.machine =
        { pkgs, ... }:
        {
          imports = [ (testHost { desktop = "none"; }) ];
          virtualisation.memorySize = 2048;
          environment.systemPackages = [
            pkgs.git
            commands
          ];
          users.users.alice.linger = true;
          # Stands in for a long-running automatic home upgrade.
          systemd.user.services.home-manager-auto-upgrade = {
            serviceConfig.Type = "oneshot";
            script = "sleep infinity";
          };
        };
      testScript = ''
        def alice(cmd):
            return f"su - alice -c 'export XDG_RUNTIME_DIR=/run/user/$(id -u alice); {cmd} 2>&1'"
        git = "git -c user.name=t -c user.email=t@t -C"
        def state(flake):
            return machine.succeed(f"md5sum ~alice/{flake}/flake.lock; readlink ~alice/.local/state/nix/profiles/home-manager || true")
        def commit(repo, old, new):
            machine.succeed(alice(f"sed -i s/{old}/{new}/ ~/{repo}/flake.nix && {git} ~/{repo} commit -qam {new}"))

        machine.wait_for_unit("multi-user.target")
        machine.wait_for_unit("user@1000.service")

        # Stub central: names its own revision and the overlay's, then fails instead of building.
        # Two home flakes, without (home) and with (home-overlay) a private overlay.
        machine.succeed(alice(" && ".join([
            "mkdir -p ~/central ~/private ~/home ~/home-overlay",
            "echo \"{ outputs = _: { lib.mkHome = a: throw \\\"stub central one, overlay \\''${a.private.rev or \\\"none\\\"}\\\"; }; }\" > ~/central/flake.nix",
            "echo \"{ outputs = _: { homeModules.default = { }; }; } # one\" > ~/private/flake.nix",
            f"{git} ~/central init -q && {git} ~/central add . && {git} ~/central commit -qm one",
            f"{git} ~/private init -q && {git} ~/private add . && {git} ~/private commit -qm one",
            "echo \"{ inputs.central.url = \\\"git+file:///home/alice/central\\\"; outputs = { central, ... }: { homeConfigurations.alice = central.lib.mkHome { }; }; }\" > ~/home/flake.nix",
            "echo \"{ inputs.central.url = \\\"git+file:///home/alice/central\\\"; inputs.private.url = \\\"git+file:///home/alice/private\\\"; outputs = { central, private, ... }: { homeConfigurations.alice = central.lib.mkHome { inherit private; }; }; }\" > ~/home-overlay/flake.nix",
            "nix flake lock ~/home && nix flake lock ~/home-overlay",
            # The commands use ~/.config/home-manager.
            "mkdir -p ~/.config && ln -s ~/home ~/.config/home-manager",
        ])))

        with subtest("build failure after a central update leaves lock and profile unchanged"):
            commit("central", "one", "two")
            before = state("home")
            out = machine.fail(alice("home-upgrade"))
            # nix wrote the bumped lock before failing; the command must have restored it.
            assert "Updated input 'central'" in out, out
            assert "stub central two" in out and "nothing was changed" in out, out
            assert state("home") == before, f"{before} != {state('home')}"

        with subtest("refuses while the automatic upgrade runs"):
            machine.succeed(alice("systemctl --user start --no-block home-manager-auto-upgrade.service"))
            machine.wait_until_succeeds(alice("systemctl --user show -P ActiveState home-manager-auto-upgrade.service | grep -qx activating"), timeout=30)
            before = state("home")
            out = machine.fail(alice("home-upgrade"))
            assert "automatic upgrade is running" in out, out
            assert state("home") == before
            machine.succeed(alice("systemctl --user stop home-manager-auto-upgrade.service"))

        with subtest("wrong arguments change nothing"):
            before = state("home")
            out = machine.fail(alice("home-upgrade --private"))
            assert "no private overlay" in out, out
            out = machine.fail(alice("home-upgrade --now"))
            assert "usage: nixos-central-upgrade [--private]" in out, out
            assert state("home") == before

        with subtest("--private updates only the overlay"):
            machine.succeed(alice("ln -sfn ~/home-overlay ~/.config/home-manager"))
            commit("central", "two", "three")
            commit("private", "one", "two")
            new_rev = machine.succeed(alice(f"{git} ~/private rev-parse HEAD")).strip()
            before = state("home-overlay")
            out = machine.fail(alice("home-upgrade-overlay --private"))
            assert "Updated input 'private'" in out and "Updated input 'central'" not in out, out
            # central stays at the locked revision ("one"), the overlay is the new one.
            assert f"stub central one, overlay {new_rev}" in out and "nothing was changed" in out, out
            assert state("home-overlay") == before, f"{before} != {state('home-overlay')}"
      '';
    };

  # nixos-central-private setup changes nothing when the overlay can't be read or
  # the configuration with it can't be activated (offline VM: it can't build).
  # The successful setup is covered by the e2e test.
  private-setup-failures = runTest {
    name = "nixos-central-private-setup-failures";
    nodes.machine =
      { pkgs, ... }:
      {
        imports = [ (testHost { desktop = "none"; }) ];
        virtualisation.memorySize = 2048;
        environment.systemPackages = [ pkgs.git ];
      };
    testScript = ''
      git = "git -c user.name=t -c user.email=t@t -C /tmp/private"
      def state():
          return machine.succeed("md5sum /etc/nixos/flake.nix /etc/nixos/flake.lock")

      machine.wait_for_unit("multi-user.target")
      # /etc/nixos as the installer writes it.
      machine.succeed(
          "mkdir -p /etc/nixos /tmp/private",
          "sed -e 's|@CENTRAL@|github:tran-engineering/nixos-central|' -e 's|@HOSTNAME@|machine|g' -e 's|@USER@|alice|' "
          + "-e 's|@DESKTOP@|none|' -e 's|@DESKTOPS@|none|' -e 's|@DISK@|/dev/vda|' -e 's|@STATE_VERSION@|26.05|' "
          + "${../templates/host/flake.nix} > /etc/nixos/flake.nix",
          "echo '{}' > /etc/nixos/flake.lock",
          "echo '{ outputs = _: { homeModules.default = { }; }; }' > /tmp/private/flake.nix",
          f"{git} init -q && {git} add . && {git} commit -qm one",
      )

      with subtest("unreachable overlay"):
          before = state()
          out = machine.fail("nixos-central-private setup git+file:///tmp/no-such-repo 2>&1")
          assert "Cannot read git+file:///tmp/no-such-repo" in out and "/home/alice/.ssh/id_ed25519" in out, out
          assert state() == before

      with subtest("activation fails: flake and lock restored"):
          out = machine.fail("nixos-central-private setup git+file:///tmp/private 2>&1")
          assert "Restored /etc/nixos/flake.nix" in out, out
          assert state() == before

      with subtest("remove without overlay"):
          out = machine.fail("nixos-central-private remove 2>&1")
          assert "has no private overlay" in out, out
          assert state() == before
    '';
  };

  # On an installed NixOS machine, both installers refuse before changing anything
  # (and before asking for root).
  home-installer-refuses-nixos = runTest {
    name = "nixos-central-home-installer-refuses-nixos";
    nodes.machine = {
      imports = [ (testHost { desktop = "none"; }) ];
    };
    testScript = ''
      machine.wait_for_unit("multi-user.target")
      as_alice = "su - alice -c 'bash {} 2>&1'"

      out = machine.fail(as_alice.format("${../installer/home-only.sh}"))
      assert "This is NixOS" in out and "nixos-central-upgrade" in out, out
      machine.fail("test -e /home/alice/.config/home-manager")

      out = machine.fail(as_alice.format("${../installer/install.sh}"))
      assert "Boot the USB image first" in out and "sudo" not in out, out
    '';
  };

  # The update notice of a standalone home, against fake state.
  update-notice-script =
    let
      notice =
        (central.mkHome {
          user = "alice";
          homeDirectory = "/home/alice";
          stateVersion = central.release;
          inherit system;
        }).config.nixos-central.updateNotice.package;
    in
    pkgs.runCommand "update-notice-script" { } ''
      set -euo pipefail
      now=$(date +%s)
      day=86400
      mkdir -p p gen1 gen2
      ln -s "$PWD/gen1" p/home-manager-1-link
      ln -s "$PWD/gen2" p/home-manager-2-link
      ln -s home-manager-2-link p/home-manager
      touch -h -d @$((now - 20 * day)) p/home-manager-1-link
      echo "{\"nodes\":{\"central\":{\"locked\":{\"lastModified\":$((now - 16 * day))}}}}" > flake.lock
      export NIXOS_CENTRAL_NOTICE_PROFILE=$PWD/p/home-manager NIXOS_CENTRAL_NOTICE_LOCK=$PWD/flake.lock \
        NIXOS_CENTRAL_NOTICE_STAMP=$PWD/stamp NIXOS_CENTRAL_NOTICE_NOW=$now
      # Never any error output, and exit status 0 (recorded in ./status).
      notice() { ${lib.getExe notice} 2>stderr; echo $? > status; }
      expect() {
        [ "$1" = "$2" ] || { printf 'expected: %s\n     got: %s\n' "$1" "$2"; exit 1; }
        [ ! -s stderr ] && [ "$(cat status)" = 0 ] || { cat stderr; echo "exit status $(cat status)"; exit 1; }
      }

      # stale: all three ages and the home-manager hint
      touch -h -d @$((now - 15 * day)) p/home-manager-2-link
      touch -d @$((now - 9 * day)) stamp
      expect "nixos-central: last successful update 9 days ago (home configuration installed 15 days ago, central revision committed 16 days ago).
      Check the daily update: systemctl --user status home-manager-auto-upgrade" "$(notice)"

      # threshold set by the profile
      expect "" "$(NIXOS_CENTRAL_NOTICE_DAYS=14 notice)"
      expect "" "$(NIXOS_CENTRAL_NOTICE_DAYS=0 notice)"

      # recent successful update, although generation and central revision are old
      touch -d @$((now - day)) stamp
      expect "" "$(notice)"

      # recent generation (manual switch), although the recorded update is old
      touch -d @$((now - 9 * day)) stamp
      touch -h -d @$((now - 2 * day)) p/home-manager-2-link
      expect "" "$(notice)"

      # unreadable lock file: central age left out
      touch -h -d @$((now - 15 * day)) p/home-manager-2-link
      expect "nixos-central: last successful update 9 days ago (home configuration installed 15 days ago)." \
        "$(NIXOS_CENTRAL_NOTICE_LOCK=$PWD/missing notice | head -1)"

      # nothing known: silent
      expect "" "$(HOME=$PWD USER=nobody NIXOS_CENTRAL_NOTICE_STAMP=$PWD/none NIXOS_CENTRAL_NOTICE_PROFILE=$PWD/none notice)"

      touch $out
    '';

  # New terminals of the primary user tell when updates stopped; successful
  # automatic upgrades are recorded.
  update-notice = runTest {
    name = "nixos-central-update-notice";
    nodes.machine =
      { lib, pkgs, ... }:
      {
        imports = [ (testHost { desktop = "none"; }) ];
        virtualisation.memorySize = 2048;
        virtualisation.additionalPaths = [ (pkgs.writeTextDir "fake-system" "staged") ];
        # Stands in for the upgrade: succeeds once /tmp/upgrade-ok exists.
        systemd.services.nixos-upgrade.script = lib.mkForce "test -e /tmp/upgrade-ok";
      };
    testScript =
      { nodes, ... }:
      let
        fake = builtins.head nodes.machine.virtualisation.additionalPaths;
      in
      ''
        def terminal():
            return machine.succeed("su - alice -c 'bash -i -c true' 2>/dev/null")

        machine.wait_for_unit("multi-user.target")
        machine.succeed("systemctl stop nixos-upgrade.timer nixos-upgrade.service")
        machine.succeed("rm -f /var/lib/nixos-central/last-update")
        # An installed machine whose last update was 15 days ago.
        machine.succeed(
            "nix-env -p /nix/var/nix/profiles/system --set $(readlink -f /run/booted-system)",
            "touch -h -d '15 days ago' /nix/var/nix/profiles/system-1-link",
            "mkdir -p /etc/nixos",
            "echo \"{\\\"nodes\\\":{\\\"central\\\":{\\\"locked\\\":{\\\"lastModified\\\":$(date -d '16 days ago' +%s)}}}}\" > /etc/nixos/flake.lock",
        )

        with subtest("stale: notice with ages and upgrade hint"):
            out = terminal()
            assert "last successful update 15 days ago (running system installed 15 days ago, central revision committed 16 days ago)" in out, out
            assert "nixos-central-upgrade" in out, out

        with subtest("not in non-interactive shells"):
            out = machine.succeed("su - alice -c 'bash -c true' 2>&1")
            assert "nixos-central" not in out, out

        with subtest("staged generation: reboot hint"):
            machine.succeed(
                "nix-env -p /nix/var/nix/profiles/system --set ${fake}",
                "touch -h -d '8 days ago' /nix/var/nix/profiles/system-2-link",
            )
            out = terminal()
            assert "last successful update 8 days ago" in out and "reboot" in out, out

        with subtest("failed upgrade is not recorded"):
            machine.fail("systemctl start nixos-upgrade.service")
            machine.fail("test -e /var/lib/nixos-central/last-update")
            assert "last successful update 8 days ago" in terminal()

        with subtest("successful upgrade is recorded: no notice"):
            machine.succeed("touch /tmp/upgrade-ok", "systemctl start nixos-upgrade.service")
            machine.succeed("test -e /var/lib/nixos-central/last-update")
            out = terminal()
            assert "nixos-central" not in out, out
      '';
  };

  # Weekly garbage collection keeps rollback targets: the generations of the last
  # 30 days, the one active 30 days ago, and the booted/running one.
  gc =
    let
      disabled = lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          (testHost { desktop = "none"; })
          { nixos-central.gc.enable = false; }
        ];
      };
    in
    assert lib.assertMsg (
      !(disabled.config.systemd.timers ? nixos-central-gc)
    ) "nixos-central.gc.enable = false must remove the timer";
    runTest {
      name = "nixos-central-gc";
      nodes.machine =
        { lib, ... }:
        {
          imports = [ (testHost { desktop = "none"; }) ];
          virtualisation.memorySize = 2048;
          # A real ESP, so the boot menu can be checked.
          virtualisation.useBootLoader = true;
          virtualisation.useEFIBoot = true;
        };
      testScript = ''
        system = "/nix/var/nix/profiles/system"

        def fake_generation(n):
            """A store path that looks like a system (all of the real one but bin/)."""
            return machine.succeed(
                f"d=/tmp/fake-{n}; mkdir $d && "
                f"for f in /run/booted-system/*; do [ $(basename $f) = bin ] || ln -s $(readlink -f $f) $d/; done && "
                f"echo {n} > $d/fake && nix-store --add $d"
            ).strip()

        def set_generation(path, days_ago):
            machine.succeed(f"nix-env -p {system} --set {path}")
            n = int(machine.succeed(f"readlink {system}").strip().split("-")[1])
            machine.succeed(f"touch -h -d '{days_ago} days ago' {system}-{n}-link")
            return n

        def generations():
            return sorted(int(l.split("-")[1]) for l in machine.succeed("ls /nix/var/nix/profiles | grep '^system-.*-link$'").split())

        def entries():
            return machine.succeed("ls /boot/loader/entries").split()

        machine.wait_for_unit("multi-user.target")
        machine.succeed("systemctl list-timers nixos-central-gc.timer | grep nixos-central-gc")
        machine.succeed("systemctl stop nixos-upgrade.timer nixos-central-gc.timer")
        real = machine.succeed("readlink -f /run/booted-system").strip()

        # The installed system (booted and running), 60 days old.
        installed = generations()
        for n in installed:
            machine.succeed(f"touch -h -d '60 days ago' {system}-{n}-link")

        with subtest("old generations go, rollback targets stay"):
            fakes = [fake_generation(i) for i in (1, 2, 3)]
            g45, g35, g20 = [set_generation(path, days) for path, days in zip(fakes, (45, 35, 20))]
            current = set_generation(real, 2)
            machine.succeed(f"{system}/bin/switch-to-configuration boot")
            assert any(f"generation-{g45}." in e for e in entries()), entries()

            machine.succeed("systemctl start nixos-central-gc.service")
            after = generations()
            assert g45 not in after, after
            # active at the cutoff, younger, current, booted
            for n in (g35, g20, current, *installed):
                assert n in after, f"{n} missing from {after}"
            machine.fail(f"test -e {fakes[0]}")
            machine.succeed(f"test -e {fakes[1]}")
            listed = entries()
            assert not any(f"generation-{g45}." in e for e in listed), listed
            assert any(f"generation-{g35}." in e for e in listed), listed
            machine.succeed(f"grep -q 'nixos-generation-{current}' /boot/loader/loader.conf")

        with subtest("the booted and running generation stays, although staged ones are newer"):
            for n, days in ((g35, 60), (g20, 55), (current, 50)):
                machine.succeed(f"touch -h -d '{days} days ago' {system}-{n}-link")
            g_staged_old = set_generation(fake_generation(5), 45)
            g_staged_new = set_generation(fake_generation(6), 1)
            machine.succeed("systemctl start nixos-central-gc.service")
            after = generations()
            assert g35 not in after and g20 not in after, after
            for n in (current, *installed, g_staged_old, g_staged_new):
                assert n in after, f"{n} missing from {after}"

        with subtest("the user's personal profile is collected by the user"):
            alice = "su - alice -c"
            machine.succeed("loginctl enable-linger alice")
            machine.wait_for_unit("user@1000.service")
            prof = "/home/alice/.local/state/nix/profiles/profile"
            machine.succeed(f"{alice} 'mkdir -p $(dirname {prof})'")

            def personal_generation(n, days_ago):
                path = machine.succeed(f"{alice} 'd=$(mktemp -d); echo {n} > $d/fake; nix-store --add $d'").strip()
                machine.succeed(f"{alice} 'nix-env -p {prof} --set {path}'")
                g = int(machine.succeed(f"readlink {prof}").strip().split("-")[-2])
                machine.succeed(f"touch -h -d '{days_ago} days ago' {prof}-{g}-link")
                return g

            p70, p60, p40, p3 = [personal_generation(n, n) for n in (70, 60, 40, 3)]
            machine.succeed("systemctl --user -M alice@ start nix-gc.service")
            after = sorted(int(l.split("-")[-2]) for l in machine.succeed(f"ls -d {prof}-*-link").split())
            # active at the cutoff, and current
            assert after == [p40, p3], after
      '';
    };

  reboot-notify-kde = rebootNotify { desktop = "kde"; };
  reboot-notify-gnome = rebootNotify { desktop = "gnome"; };
}
