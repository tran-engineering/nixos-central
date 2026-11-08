# VM tests for the central configuration. `checks` run with `nix flake check`
# (or `nix build .#checks.x86_64-linux.<name>`); `desktop` ones boot full
# desktops and run on demand (`nix build .#desktopTests.<name>`).
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
  # Stands in for a desktop's notification server on the session bus: logs the
  # title and body of every notification to the journal.
  notificationStub =
    let
      python = pkgs.python3.withPackages (ps: [ ps.pygobject3 ]);
    in
    pkgs.writeScript "notification-stub" ''
      #!${python}/bin/python3
      from gi.repository import Gio, GLib

      XML = """
      <node><interface name="org.freedesktop.Notifications">
        <method name="Notify">
          <arg type="s" direction="in"/><arg type="u" direction="in"/><arg type="s" direction="in"/>
          <arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="as" direction="in"/>
          <arg type="a{sv}" direction="in"/><arg type="i" direction="in"/><arg type="u" direction="out"/>
        </method>
        <method name="CloseNotification"><arg type="u" direction="in"/></method>
        <method name="GetCapabilities"><arg type="as" direction="out"/></method>
        <method name="GetServerInformation">
          <arg type="s" direction="out"/><arg type="s" direction="out"/>
          <arg type="s" direction="out"/><arg type="s" direction="out"/>
        </method>
      </interface></node>
      """

      def call(conn, sender, path, iface, method, params, invocation):
          if method == "Notify":
              args = params.unpack()
              print(f"notification: {args[3]} | {args[4]}", flush=True)
              invocation.return_value(GLib.Variant("(u)", (1,)))
          elif method == "GetCapabilities":
              invocation.return_value(GLib.Variant("(as)", (["body"],)))
          elif method == "GetServerInformation":
              invocation.return_value(GLib.Variant("(ssss)", ("stub", "test", "1", "1.2")))
          else:
              invocation.return_value(None)

      def bus_acquired(conn, name):
          info = Gio.DBusNodeInfo.new_for_xml(XML).interfaces[0]
          conn.register_object("/org/freedesktop/Notifications", info, call, None, None)

      Gio.bus_own_name(Gio.BusType.SESSION, "org.freedesktop.Notifications", 0, bus_acquired, None, None)
      GLib.MainLoop().run()
    '';

  # A staged generation produces exactly one notification per generation.
  # With desktop "none", a stub notification server stands in for the desktop
  # (checks the logic, fast); with a real desktop, its own server and session
  # are used (checks the integration, slow). `node` and `extraScript` add
  # desktop-specific configuration and checks; `sessionScript` runs as soon as
  # the graphical session is up, before the notification server is awaited.
  rebootNotify =
    {
      desktop,
      node ? { },
      sessionScript ? "",
      extraScript ? "",
    }:
    let
      headless = desktop == "none";
    in
    runTest {
      name = "nixos-central-reboot-notify-${desktop}";
      nodes.machine =
        { lib, pkgs, ... }:
        {
          imports = [
            (testHost { inherit desktop; })
            node
            (
              if headless then
                {
                  nixos-central.rebootNotify.enable = true;
                  users.users.alice.linger = true;
                  virtualisation.memorySize = 2048;
                  systemd.user.services.notification-stub = {
                    wantedBy = [ "default.target" ];
                    environment.GI_TYPELIB_PATH = lib.makeSearchPath "lib/girepository-1.0" [
                      pkgs.glib.out
                      pkgs.gobject-introspection
                    ];
                    serviceConfig.ExecStart = notificationStub;
                  };
                }
              else
                {
                  services.displayManager.autoLogin = {
                    enable = true;
                    user = "alice";
                  };
                  virtualisation.memorySize = 4096;
                  virtualisation.cores = 2;
                }
            )
          ];
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
        ''
        + (
          if headless then
            ''
              # No graphical session: the timer never starts, the service is started directly.
              machine.wait_for_unit("user@1000.service")
            ''
          else
            ''
              machine.wait_until_succeeds(f"{user} is-active graphical-session.target", timeout=900)
              machine.wait_until_succeeds(f"{user} is-active {unit}.timer")
              ${sessionScript}
            ''
        )
        + ''
          # notify-send needs a notification server on alice's session bus
          machine.wait_until_succeeds(
              "busctl --user -M alice@ call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus"
              " NameHasOwner s org.freedesktop.Notifications | grep -qx 'b true'",
              timeout=900,
          )
          ${lib.optionalString (!headless) "machine.sleep(30)"}

          with subtest("no notification without a staged update"):
              machine.succeed(f"{user} start {unit}.service")
              assert notifications() == 0

          with subtest("staged update notifies once"):
              machine.succeed("nix-env -p /nix/var/nix/profiles/system --set ${builtins.head fake}")
              machine.succeed(f"{user} start {unit}.service")
              machine.succeed(f"{user} start {unit}.service")
              assert notifications() == 1, f"expected 1 notification, got {notifications()}"
        ''
        + (
          if headless then
            ''
              shown = machine.succeed("journalctl _SYSTEMD_USER_UNIT=notification-stub.service | grep 'notification:'")
              assert shown.count("notification:") == 1, shown
              assert "Update ready – reboot when convenient | " in shown, shown
              assert "Run nixos-central diff to see what it changes." in shown, shown
            ''
          else
            ''
              # The body points to the diff command (the shown text depends on the desktop's server).
              machine.succeed("grep -q 'Run nixos-central diff' ${nodes.machine.systemd.user.services.nixos-central-reboot-notify.serviceConfig.ExecStart}")
            ''
        )
        + ''

          with subtest("after reboot into the staged generation: no notification"):
              machine.succeed("nix-env -p /nix/var/nix/profiles/system --set $(readlink -f /run/booted-system)")
              machine.succeed(f"{user} start {unit}.service")
              assert notifications() == 1

          ${extraScript}
        '';
    };
in
{
  checks = {
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

    # The docker daemon runs and the primary user reaches it without sudo.
    docker = runTest {
      name = "nixos-central-docker";
      nodes.machine = {
        imports = [ (testHost { desktop = "none"; }) ];
      };
      testScript = ''
        machine.wait_for_unit("multi-user.target")
        machine.wait_for_unit("docker.service")
        machine.succeed("su - alice -c 'docker info'")
      '';
    };

    # The firmware update daemon answers the primary user and the update list
    # is refreshed on a timer.
    fwupd = runTest {
      name = "nixos-central-fwupd";
      nodes.machine = {
        imports = [ (testHost { desktop = "none"; }) ];
      };
      testScript = ''
        machine.wait_for_unit("multi-user.target")
        machine.succeed("systemctl is-enabled fwupd-refresh.timer")
        machine.succeed("systemctl is-active fwupd-refresh.timer")
        # D-Bus activates the daemon; get-devices exits 2 when nothing is updatable
        status, out = machine.execute("su - alice -c 'fwupdmgr get-devices --json'")
        assert status in (0, 2), (status, out)
        machine.succeed("systemctl is-active fwupd.service")
      '';
    };

    # Flatpak with Flathub, offline (the remote comes from the `flathub`
    # input, already in the store), its update timers, and the AppImage
    # binfmt registrations. Installing from Flathub and running a real
    # AppImage need network and a desktop and are checked by hand. `machine`
    # stands in for a graphical desktop (the switch set by hand, a portal
    # because Flatpak requires one); `plain` is a desktop-less machine, which
    # gets none of it.
    desktop-apps = runTest {
      name = "nixos-central-desktop-apps";
      nodes.machine =
        { pkgs, ... }:
        {
          imports = [ (testHost { desktop = "none"; }) ];
          nixos-central.desktopApps.enable = true;
          xdg.portal = {
            enable = true;
            extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
            config.common.default = "*";
          };
        };
      nodes.plain = {
        imports = [ (testHost { desktop = "none"; }) ];
      };
      testScript = ''
        start_all()
        machine.wait_for_unit("multi-user.target")
        machine.wait_for_unit("flatpak-flathub.service")
        machine.succeed("flatpak remotes --system --columns=name | grep -x flathub")
        machine.succeed("su - alice -c 'flatpak remotes --columns=name' | grep -x flathub")

        # Updates daily and once after each start of the service manager: system
        # timer, and the user timer in alice's manager.
        machine.succeed("systemctl is-enabled flatpak-update.timer")
        machine.succeed("systemctl is-active flatpak-update.timer")
        machine.succeed("systemctl show -p TimersMonotonic flatpak-update.timer | grep OnStartupUSec")
        machine.succeed("loginctl enable-linger alice")
        machine.wait_for_unit("user@1000.service")
        machine.succeed("systemctl --user -M alice@ is-enabled flatpak-update.timer")
        machine.succeed("systemctl --user -M alice@ is-active flatpak-update.timer")
        machine.succeed("systemctl --user -M alice@ show -p TimersMonotonic flatpak-update.timer | grep OnStartupUSec")

        # An offline run may fail, but leaves the installation usable.
        status, out = machine.execute("systemctl start flatpak-update.service")
        print(f"offline flatpak update: exit {status}")
        machine.succeed("flatpak list --system")
        machine.succeed("flatpak remotes --system --columns=name | grep -x flathub")

        # AppImages of both types are handed to appimage-run.
        for kind in ("appimage_type_1", "appimage_type_2"):
            machine.succeed(f"grep -x enabled /proc/sys/fs/binfmt_misc/{kind}")
            machine.succeed(f"grep -x 'interpreter /run/binfmt/{kind}' /proc/sys/fs/binfmt_misc/{kind}")
            machine.succeed(f"readlink /run/binfmt/{kind} | grep '/bin/appimage-run$'")

        plain.wait_for_unit("multi-user.target")
        plain.fail("command -v flatpak")
        plain.fail("ls /proc/sys/fs/binfmt_misc/ | grep -i appimage")
      '';
    };

    # The nixos-central command with stub subcommands: help, dispatch, errors,
    # menu entries, and the generated completions (syntax; bash and fish run).
    # The menu itself (gum) needs a terminal and is checked by hand.
    command =
      let
        stub = name: pkgs.writeShellScriptBin "stub-${name}" ''echo "${name}: $*"'';
        nixos-central = pkgs.callPackage ../command {
          commands = {
            one = {
              package = stub "one";
              description = "First stub";
              usage = "[--flag]";
              order = 10;
              chooser = true;
              completions."" = [ "--flag" ];
            };
            two = {
              package = stub "two";
              description = "Second stub";
              usage = "[add <x> [--name N] | drop]";
              order = 20;
              chooser = true;
              completions = {
                "" = [
                  "add"
                  "drop"
                ];
                add = [ "--name" ];
              };
            };
            hidden = {
              package = stub "hidden";
              description = "Not in the menu";
              usage = "<arg>";
              order = 30;
              chooser = false;
              completions = { };
            };
          };
        };
      in
      assert lib.assertMsg (
        map (lib.head) (map (lib.splitString " ") nixos-central.menuItems) == [
          "one"
          "two"
        ]
      ) "menu: ${toString nixos-central.menuItems}";
      pkgs.runCommand "command"
        {
          nativeBuildInputs = [
            nixos-central
            pkgs.zsh
            pkgs.fish
          ];
        }
        ''
          set -euo pipefail
          export HOME=$TMPDIR
          expect() { [ "$1" = "$2" ] || { printf 'expected: %s\n     got: %s\n' "$1" "$2"; exit 1; }; }

          # help: every subcommand with usage and description, exit 0
          for h in help -h --help; do
            msg=$(nixos-central $h)
            for line in "one [--flag]" "First stub" "two [add <x> [--name N] | drop]" "hidden <arg>" "Not in the menu"; do
              grep -qF -- "$line" <<<"$msg" || { echo "$h lacks: $line"; echo "$msg"; exit 1; }
            done
          done

          # arguments are passed on unchanged
          expect "two: add a b --name 'c d'" "$(nixos-central two add a b --name "'c d'")"
          expect "hidden: " "$(nixos-central hidden)"

          # unknown subcommand: error, help on stderr, exit 2
          status=0; msg=$(nixos-central frobnicate 2>&1 >/dev/null) || status=$?
          expect 2 "$status"
          grep -q "'frobnicate' is not a subcommand" <<<"$msg"
          grep -q "one \[--flag\]" <<<"$msg"

          # no arguments without a terminal: help on stderr, exit 2, no menu
          status=0; msg=$(nixos-central </dev/null 2>&1 >/dev/null) || status=$?
          expect 2 "$status"
          grep -q "usage: nixos-central" <<<"$msg"

          # completions
          share=${nixos-central}/share
          bash -n $share/bash-completion/completions/nixos-central
          zsh -n $share/zsh/site-functions/_nixos-central
          fish --no-execute $share/fish/vendor_completions.d/nixos-central.fish

          bash_complete() {
            ${pkgs.bashInteractive}/bin/bash -c 'source "$1"; shift; COMP_WORDS=("$@"); COMP_CWORD=$(($# - 1)); _nixos_central; echo "''${COMPREPLY[*]}"' \
              _ $share/bash-completion/completions/nixos-central nixos-central "$@"
          }
          expect "one two hidden" "$(bash_complete "")"
          expect "two" "$(bash_complete t)"
          expect "--flag" "$(bash_complete one "")"
          expect "add drop" "$(bash_complete two "")"
          expect "--name" "$(bash_complete two add x "")"
          expect "" "$(bash_complete two add --name "")"
          expect "" "$(bash_complete hidden "")"

          fish_complete() {
            fish -c "source $share/fish/vendor_completions.d/nixos-central.fish; complete -C '$1' | string replace -r '\t.*' ''' | string join ' '"
          }
          expect "hidden one two" "$(fish_complete 'nixos-central ')"
          expect "add drop" "$(fish_complete 'nixos-central two ')"
          expect "--name" "$(fish_complete 'nixos-central two add x ')"

          touch $out
        '';

    # The nixos-central command of a standalone home, activated for real on a
    # plain NixOS VM without the central modules (standing in for another
    # distribution with Nix): its subcommands, the old names gone, and
    # completions found where bash, fish and zsh (home-manager) look for them.
    home-command =
      let
        home =
          (central.mkHome {
            user = "alice";
            homeDirectory = "/home/alice";
            stateVersion = central.release;
            inherit system;
          }).activationPackage;
        bashComplete = pkgs.writeText "complete.bash" ''
          __load_completion nixos-central
          COMP_WORDS=(nixos-central ""); COMP_CWORD=1
          _nixos_central
          echo "completions: ''${COMPREPLY[*]}"
        '';
        fishComplete = pkgs.writeText "complete.fish" ''
          echo completions: (complete -C 'nixos-central ' | string replace -r '\t.*' "" | string join ' ')
        '';
        # What home-manager's zsh module adds to fpath.
        zshFpath = pkgs.writeText "fpath.zsh" ''
          for p in ''${(z)NIX_PROFILES}; do
            [[ -e $p/share/zsh/site-functions/_nixos-central ]] && print found
          done
        '';
      in
      runTest {
        name = "nixos-central-home-command";
        nodes.machine =
          { pkgs, ... }:
          {
            users.users.alice = {
              isNormalUser = true;
              linger = true;
            };
            environment.systemPackages = [
              pkgs.fish
              pkgs.zsh
            ];
            nix.settings.experimental-features = [
              "nix-command"
              "flakes"
            ];
            virtualisation.memorySize = 2048;
            virtualisation.diskSize = 4096;
            virtualisation.additionalPaths = [ home ];
          };
        testScript = ''
          def alice(cmd):
              return f"su - alice -c 'export XDG_RUNTIME_DIR=/run/user/$(id -u alice); {cmd} 2>&1'"

          machine.wait_for_unit("user@1000.service")
          machine.succeed(alice("${home}/activate"))
          # The home's flake, as home-only.sh writes it (read by `nixos-central private`).
          machine.succeed(
              "mkdir -p /home/alice/.config/home-manager",
              "echo '{ inputs.central.url = \"git+https://github.com/tran-engineering/nixos-central\"; }' > /home/alice/.config/home-manager/flake.nix",
              "chown -R alice: /home/alice/.config",
          )

          with subtest("one command with the home's subcommands"):
              out = machine.succeed(alice("nixos-central --help"))
              for line in ("upgrade [--private]", "diff ", "status ", "private [setup"):
                  assert f"\n  {line}" in out, out
              assert "\n  try" not in out, out
              status, out = machine.execute(alice("nixos-central try main"))
              assert status == 2 and "not a subcommand" in out, (status, out)
              assert "last successful update" in machine.succeed(alice("nixos-central status"))
              assert "No private overlay" in machine.succeed(alice("nixos-central private"))

          with subtest("old names gone"):
              for old in ("upgrade", "diff", "private", "update-notice"):
                  machine.fail(alice(f"type -P nixos-central-{old}"))

          with subtest("completions"):
              out = machine.succeed(alice("bash -i ${bashComplete}"))
              assert "completions: upgrade diff status private" in out, out
              out = machine.succeed(alice("fish ${fishComplete}"))
              assert "completions: diff private status upgrade" in out, out
              assert "found" in machine.succeed(alice("zsh -f ${zshFpath}"))
        '';
      };

    # nixos-central diff compares the staged generation, or else the last two.
    diff =
      let
        staged = pkgs.buildEnv {
          name = "fake-staged-system";
          paths = [
            pkgs.hello
            pkgs.jq
          ];
        };
      in
      runTest {
        name = "nixos-central-diff";
        nodes.machine = {
          imports = [ (testHost { desktop = "none"; }) ];
          virtualisation.memorySize = 2048;
          virtualisation.additionalPaths = [ staged ];
        };
        testScript = ''
          system = "/nix/var/nix/profiles/system"
          diff = "su - alice -c 'nixos-central diff 2>&1'"
          def set_generation(path):
              machine.succeed(f"nix-env -p {system} --set {path}")

          machine.wait_for_unit("multi-user.target")
          machine.succeed("systemctl stop nixos-upgrade.timer")

          with subtest("nothing to compare"):
              # Test VMs boot without a system profile.
              assert "No earlier generation to compare with." in machine.succeed(diff)
              set_generation("$(readlink -f /run/booted-system)")
              assert "No earlier generation to compare with." in machine.succeed(diff)

          with subtest("staged update: running system -> staged"):
              set_generation("${staged}")
              out = machine.succeed(diff)
              assert "Pending on next reboot (generation 2):" in out, out
              assert "jq" in out, out

          with subtest("update in use: previous -> newest generation"):
              set_generation("$(readlink -f /run/booted-system)")
              out = machine.succeed(diff)
              assert "Changes from generation 2 to 3:" in out, out
              assert "jq" in out, out

          with subtest("collected generations are skipped"):
              machine.succeed(f"rm {system}-2-link")
              out = machine.succeed(diff)
              assert "Changes from generation 1 to 3:" in out, out

          with subtest("unknown argument"):
              status, out = machine.execute("su - alice -c 'nixos-central diff --all 2>&1'")
              assert status == 2 and "usage: nixos-central diff" in out, (status, out)
        '';
      };

    # nixos-central diff of standalone homes compares the last two home generations.
    home-diff =
      let
        generation =
          name: paths:
          pkgs.buildEnv {
            name = "fake-home-${name}";
            inherit paths;
          };
        old = generation "old" [ pkgs.hello ];
        new = generation "new" [
          pkgs.hello
          pkgs.jq
        ];
      in
      runTest {
        name = "nixos-central-home-diff";
        nodes.machine = {
          imports = [ (testHost { desktop = "none"; }) ];
          virtualisation.memorySize = 2048;
          virtualisation.additionalPaths = [
            old
            new
          ];
          # The home variant under another name than the machine's subcommand.
          environment.systemPackages = [
            (pkgs.runCommand "home-diff-command" { } ''
              mkdir -p $out/bin
              ln -s ${pkgs.callPackage ../diff { mode = "home"; }}/bin/nixos-central-diff $out/bin/home-diff
            '')
          ];
        };
        testScript = ''
          def alice(cmd):
              return f"su - alice -c '{cmd} 2>&1'"
          profile = "~/.local/state/nix/profiles/home-manager"

          machine.wait_for_unit("multi-user.target")

          with subtest("nothing to compare"):
              assert "No earlier generation to compare with." in machine.succeed(alice("home-diff"))
              machine.succeed(alice(f"mkdir -p $(dirname {profile}) && nix-env -p {profile} --set ${old}"))
              assert "No earlier generation to compare with." in machine.succeed(alice("home-diff"))

          with subtest("previous -> current generation"):
              machine.succeed(alice(f"nix-env -p {profile} --set ${new}"))
              out = machine.succeed(alice("home-diff"))
              assert "Changes from generation 1 to 2:" in out, out
              assert "jq" in out, out

          with subtest("unknown argument"):
              status, out = machine.execute(alice("home-diff --all"))
              assert status == 2 and "usage: nixos-central diff" in out, (status, out)
        '';
      };

    # nixos-central upgrade changes nothing when it fails or an auto-upgrade runs.
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
            preStart = lib.mkForce "";
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
            out = machine.fail("nixos-central upgrade 2>&1")
            # nix wrote the bumped lock before failing; the command must have restored it.
            assert "Updated input 'central'" in out, out
            assert "broken central" in out and "nothing was changed" in out, out
            assert state() == before, f"{before} != {state()}"

        with subtest("refuses while the automatic upgrade runs"):
            machine.succeed("systemctl start --no-block nixos-upgrade.service")
            machine.wait_until_succeeds("systemctl show -P ActiveState nixos-upgrade.service | grep -qx activating", timeout=30)
            before = state()
            out = machine.fail("nixos-central upgrade 2>&1")
            assert "automatic upgrade is running" in out, out
            assert state() == before
            machine.succeed("systemctl stop nixos-upgrade.service")

        with subtest("--private without an overlay changes nothing"):
            before = state()
            out = machine.fail("nixos-central upgrade --private 2>&1")
            assert "no private overlay" in out and "nixos-central private setup" in out, out
            assert state() == before

        with subtest("one nixos-central command, old names gone"):
            paths = machine.succeed("su - alice -c 'type -ap nixos-central'").split()
            assert len(paths) == 1, paths
            machine.fail("su - alice -c 'type -P nixos-central-upgrade'")
            machine.fail("type -P nixos-central-upgrade")
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
            out = machine.fail("nixos-central upgrade 2>&1")
            assert "Updated input 'private'" in out and f"overlay {new_rev}" in out, out
            assert state() == before, f"{before} != {state()}"

        with subtest("--private updates only the overlay"):
            machine.succeed(f"sed -i s/one/two/ /tmp/central/flake.nix && {git} /tmp/central commit -qam two")
            machine.succeed(f"echo '# three' >> /tmp/private/flake.nix && {git} /tmp/private commit -qam three")
            new_rev = machine.succeed(f"{git} /tmp/private rev-parse HEAD").strip()
            before = state()
            out = machine.fail("nixos-central upgrade --private 2>&1")
            assert "Updated input 'private'" in out and "Updated input 'central'" not in out, out
            # central stays at the locked revision ("one"), the overlay is the new one.
            assert f"stub central one, overlay {new_rev}" in out and "nothing was changed" in out, out
            assert state() == before, f"{before} != {state()}"

        with subtest("an unreachable overlay stops both upgrade paths"):
            machine.succeed("mv /tmp/private /tmp/private-gone")
            before = state()
            out = machine.fail("nixos-central upgrade 2>&1")
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

    # nixos-central upgrade of standalone homes changes nothing when it fails, an
    # automatic upgrade runs or its arguments are wrong; --private updates only
    # the overlay. Runs in a NixOS VM (offline: a stub central can't build a home),
    # with the home commands under other names so they don't clash with NixOS's.
    home-upgrade-failures =
      let
        homeCommand =
          private:
          (central.mkHome {
            user = "alice";
            homeDirectory = "/home/alice";
            stateVersion = central.release;
            inherit system private;
          }).config.nixos-central.commands.upgrade.package;
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
              assert "usage: nixos-central upgrade [--private]" in out, out
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

    # The flake edits of `nixos-central private` and the installer (flake-edit.sh)
    # on both templates: the exact lines added, and remove restoring the file.
    private-flake-edit =
      pkgs.runCommand "private-flake-edit" { nativeBuildInputs = [ pkgs.diffutils ]; } ''
        set -euo pipefail
        die() { echo "die: $*" >&2; exit 1; }
        source ${../private/flake-edit.sh}
        render() { sed -e 's|@USER@|alice|' -e 's|@[A-Z_]*@|x|g' "$1" > "$2"; cp "$2" "$2.orig"; }
        render ${../templates/host/flake.nix} host.nix
        render ${../templates/home/flake.nix} home.nix
        added() { diff "$1.orig" "$1" | sed -n 's/^> *//p'; }
        expect() { [ "$1" = "$2" ] || { printf 'expected:\n%s\ngot:\n%s\n' "$1" "$2"; exit 1; }; }

        # NixOS with a profile: right after the user, removed again with the overlay.
        flake_add_overlay host.nix nixos 'git+ssh://git@github.com/alice/private?ref=a&b=1' developer
        expect 'inputs.private.url = "git+ssh://git@github.com/alice/private?ref=a&b=1";
        { central, private, ... }:
        profile = "developer"; # profile of the private overlay
        inherit private;' "$(added host.nix)"
        grep -q '^        profile = "developer";' host.nix   # indented like user
        grep -q '^        inherit private;' host.nix
        flake_remove_overlay host.nix nixos
        cmp host.nix host.nix.orig

        # NixOS without a profile: no profile line.
        flake_add_overlay host.nix nixos git+ssh://git@github.com/alice/private
        ! grep -q 'profile = ' host.nix
        flake_remove_overlay host.nix nixos
        cmp host.nix host.nix.orig

        # Standalone home: the template has no profile line; it goes after the
        # user and is removed again with the overlay.
        ! grep -q 'profile = ' home.nix
        flake_add_overlay home.nix home git+ssh://git@github.com/alice/private kt
        expect 'inputs.private.url = "git+ssh://git@github.com/alice/private";
        { central, private, ... }:
        profile = "kt"; # profile of the private overlay
        inherit private;' "$(added home.nix)"
        grep -q '^        profile = "kt";' home.nix   # indented like user
        flake_remove_overlay home.nix home
        cmp home.nix home.nix.orig

        # Home flake from an earlier installer: its profile line is rewritten,
        # and removed with the overlay.
        sed 's|^\( *\)user = \(.*\)$|&\n\1profile = "_default"; # one of: _default|' home.nix.orig > old.nix
        flake_add_overlay old.nix home git+ssh://git@github.com/alice/private kt
        grep -q '^ *profile = "kt"; # profile of the private overlay$' old.nix
        [ "$(grep -c 'profile = ' old.nix)" -eq 1 ]
        flake_remove_overlay old.nix home
        ! grep -q 'profile = \|private' old.nix

        # A flake of another shape is refused unchanged.
        echo '{ }' > other.nix
        if (flake_add_overlay other.nix nixos u p) 2>err; then exit 1; fi
        grep -q 'does not have the expected shape' err
        expect '{ }' "$(cat other.nix)"
        touch $out
      '';

    # nixos-central private setup changes nothing when the overlay can't be read or
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
            "sed -e 's|@CENTRAL@|git+https://github.com/tran-engineering/nixos-central|' -e 's|@HOSTNAME@|machine|g' -e 's|@USER@|alice|' "
            + "-e 's|@DESKTOP@|none|' -e 's|@DESKTOPS@|none|' -e 's|@DISK@|/dev/vda|' -e 's|@STATE_VERSION@|26.05|' "
            + "${../templates/host/flake.nix} > /etc/nixos/flake.nix",
            "echo '{}' > /etc/nixos/flake.lock",
            "echo '{ outputs = _: { homeModules.default = { }; }; }' > /tmp/private/flake.nix",
            f"{git} init -q && {git} add . && {git} commit -qm one",
        )

        default = "git+ssh://git@github.com/tran-engineering/nixos-central-private"

        with subtest("state without an overlay, as a normal user"):
            before = state()
            out = machine.succeed("su - alice -c 'nixos-central private' 2>&1")
            assert "No private overlay. Add one with: nixos-central private setup" in out, out
            assert default in out, out
            assert state() == before

        with subtest("unknown action"):
            status, out = machine.execute("su - alice -c 'nixos-central private frobnicate' 2>&1")
            assert status == 2 and "Usage: nixos-central private" in out, (status, out)
            assert state() == before

        with subtest("unreachable overlay"):
            out = machine.fail("nixos-central private setup git+file:///tmp/no-such-repo 2>&1")
            assert "Cannot read git+file:///tmp/no-such-repo" in out and "/home/alice/.ssh/id_ed25519" in out, out
            assert state() == before

        with subtest("no URL: the default overlay (unreachable offline)"):
            out = machine.fail("nixos-central private setup 2>&1")
            assert f"Using the default overlay {default}" in out and f"Cannot read {default}" in out, out
            assert state() == before

        with subtest("activation fails: flake and lock restored"):
            out = machine.fail("nixos-central private setup git+file:///tmp/private 2>&1")
            assert "Restored /etc/nixos/flake.nix" in out, out
            assert state() == before

        with subtest("NixOS accepts --profile; activation fails: flake and lock restored"):
            out = machine.fail("nixos-central private setup git+file:///tmp/private --profile developer 2>&1")
            assert "only for standalone homes" not in out and "Restored /etc/nixos/flake.nix" in out, out
            assert state() == before

        with subtest("remove without overlay"):
            out = machine.fail("nixos-central private remove 2>&1")
            assert "has no private overlay" in out, out
            assert state() == before

        with subtest("state with an overlay"):
            machine.succeed("sed -i 's|^\\( *\\)inputs.central.url = .*$|&\\n\\1inputs.private.url = \"git+file:///tmp/private\";|' /etc/nixos/flake.nix")
            out = machine.succeed("su - alice -c 'nixos-central private'")
            assert "Private overlay: git+file:///tmp/private" in out, out
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
        assert "This is NixOS" in out and "nixos-central upgrade" in out, out
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
        notice() { ${lib.getExe notice} --if-stale 2>stderr; echo $? > status; }
        manual() { ${lib.getExe notice} 2>stderr; echo $? > status; }
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

        # run by hand: printed although recent, and although turned off
        expect "nixos-central: last successful update 1 day ago (home configuration installed 15 days ago, central revision committed 16 days ago).
        Check the daily update: systemctl --user status home-manager-auto-upgrade" "$(manual)"
        expect "nixos-central: last successful update 1 day ago (home configuration installed 15 days ago, central revision committed 16 days ago)." \
          "$(NIXOS_CENTRAL_NOTICE_DAYS=0 manual | head -1)"

        # recent generation (manual switch), although the recorded update is old
        touch -d @$((now - 9 * day)) stamp
        touch -h -d @$((now - 2 * day)) p/home-manager-2-link
        expect "" "$(notice)"

        # unreadable lock file: central age left out
        touch -h -d @$((now - 15 * day)) p/home-manager-2-link
        expect "nixos-central: last successful update 9 days ago (home configuration installed 15 days ago)." \
          "$(NIXOS_CENTRAL_NOTICE_LOCK=$PWD/missing notice | head -1)"

        # nothing known: silent, by hand "unknown"
        expect "" "$(HOME=$PWD USER=nobody NIXOS_CENTRAL_NOTICE_STAMP=$PWD/none NIXOS_CENTRAL_NOTICE_PROFILE=$PWD/none notice)"
        expect "nixos-central: last successful update unknown (central revision committed 16 days ago)." \
          "$(HOME=$PWD USER=nobody NIXOS_CENTRAL_NOTICE_STAMP=$PWD/none NIXOS_CENTRAL_NOTICE_PROFILE=$PWD/none manual | head -1)"

        # unknown option
        ${lib.getExe notice} --bogus 2>/dev/null && exit 1 || [ $? = 2 ]

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
          systemd.services.nixos-upgrade = {
            preStart = lib.mkForce "";
            script = lib.mkForce "test -e /tmp/upgrade-ok";
          };
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
              assert "Run nixos-central upgrade" in out, out

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

          with subtest("run by hand: printed although recent"):
              out = machine.succeed("su - alice -c 'nixos-central status'")
              assert "last successful update today" in out, out
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

    # The keyboardLayout fact reaches the console and the graphical session;
    # machines without the fact (installed before it existed) keep "us".
    keyboard-layouts =
      let
        configOf =
          layout:
          (central.mkHost {
            hostname = "machine";
            user = "alice";
            desktop = "none";
            disk = "/dev/vda";
            stateVersion = central.release;
            keyboardLayout = layout;
          }).config;
        expect =
          layout: keymap: xkbLayout: xkbVariant:
          let
            c = configOf layout;
            ok =
              c.console.keyMap == keymap
              && c.services.xserver.xkb.layout == xkbLayout
              && c.services.xserver.xkb.variant == xkbVariant;
          in
          lib.assertMsg ok
            "keyboard layout ${layout} maps to ${c.console.keyMap}, xkb ${c.services.xserver.xkb.layout}/${c.services.xserver.xkb.variant}";
      in
      assert expect "us" "us" "us" "";
      assert expect "de" "de-latin1" "de" "";
      assert expect "sg" "sg-latin1" "ch" "";
      assert expect "sf" "fr_CH-latin1" "ch" "fr";
      assert (central.mkHost {
        hostname = "machine";
        user = "alice";
        desktop = "none";
        disk = "/dev/vda";
        stateVersion = central.release;
      }).config.console.keyMap == "us";
      pkgs.writeText "keyboard-layouts" "ok";

    # Security key login (modules/base/u2f.nix): which generated PAM services
    # contain pam_u2f, in which order, and which must not. A key touch itself
    # can't be tested in a VM (no FIDO device emulation).
    u2f-pam =
      let
        configOf =
          desktop:
          (central.mkHost {
            hostname = "machine";
            user = "alice";
            inherit desktop;
            disk = "/dev/vda";
            stateVersion = central.release;
          }).config;
        graphical = [
          "kde"
          "gnome"
          "niri-noctalia"
        ];
        # The exact text written to /etc/pam.d/<svc> ("" if the service doesn't exist).
        pam = c: svc: c.security.pam.services.${svc}.text or "";
        hasU2f = c: svc: lib.hasInfix "pam_u2f" (pam c svc);
        check = cond: msg: lib.assertMsg cond "u2f-pam: ${msg}";
        # The pam_u2f auth line, bound to the fleet-wide origin, comes before the
        # first auth line containing `marker` (the password path).
        u2fBefore =
          desktop: svc: marker:
          let
            lines = lib.splitString "\n" (pam (configOf desktop) svc);
            indexOf =
              pred:
              lib.findFirst (i: pred (builtins.elemAt lines i)) null (lib.range 0 (builtins.length lines - 1));
            isAuth = l: lib.hasPrefix "auth " l;
            u2f = indexOf (l: isAuth l && lib.hasInfix "pam_u2f.so" l);
            password = indexOf (l: isAuth l && lib.hasInfix marker l);
          in
          check (
            u2f != null
            && password != null
            && u2f < password
            && lib.hasInfix "origin=pam://nixos-central" (builtins.elemAt lines u2f)
          ) "${desktop}: pam.d/${svc} needs pam_u2f (origin pam://nixos-central) before '${marker}'";
        withoutU2f =
          desktop:
          let
            c = configOf desktop;
          in
          map (
            svc:
            check (pam c svc != "") "${desktop}: pam.d/${svc} missing"
            && check (!hasU2f c svc) "${desktop}: pam.d/${svc} must not contain pam_u2f"
          ) [
            "login"
            "sudo"
            "su"
          ];
        none = configOf "none";
        noneU2fServices = lib.filter (hasU2f none) (builtins.attrNames none.security.pam.services);
        checks =
          lib.concatMap withoutU2f (graphical ++ [ "none" ])
          ++ [
            (check (noneU2fServices == [ ]) "none: pam_u2f in ${toString noneU2fServices}")
            (check (
              !builtins.any (p: lib.getName p == "pam_u2f") none.environment.systemPackages
            ) "none: pamu2fcfg (pam_u2f) must not be installed")
            # Login screens; GNOME's lock screen also uses gdm-password.
            (u2fBefore "kde" "sddm" "substack login")
            (u2fBefore "niri-noctalia" "sddm" "substack login")
            (u2fBefore "gnome" "gdm-password" "substack login")
            # Lock screens.
            (u2fBefore "kde" "kde" "pam_unix.so")
            (check (!hasU2f (configOf "gnome") "kde") "gnome: pam.d/kde must not contain pam_u2f")
            (check (!hasU2f (configOf "niri-noctalia") "kde") "niri-noctalia: pam.d/kde must not contain pam_u2f")
            (u2fBefore "niri-noctalia" "noctalia" "pam_unix.so")
            (check (
              (configOf "niri-noctalia").systemd.user.services.noctalia-shell.environment.NOCTALIA_PAM_SERVICE or null
              == "noctalia"
            ) "niri-noctalia: noctalia-shell must use the noctalia PAM service")
            (check (!hasU2f (configOf "kde") "noctalia") "kde: pam.d/noctalia must not exist")
          ]
          ++ map (
            desktop:
            check (builtins.any (p: lib.getName p == "pam_u2f") (configOf desktop).environment.systemPackages)
              "${desktop}: pamu2fcfg (pam_u2f) must be installed"
          ) graphical;
      in
      assert builtins.all (x: x) checks;
      pkgs.writeText "u2f-pam" "ok";

    reboot-notify = rebootNotify { desktop = "none"; };
  };

  # Boot full desktops (10–15 minutes each), so not part of `nix flake check`.
  desktop = {
    reboot-notify-kde = rebootNotify { desktop = "kde"; };
    reboot-notify-gnome = rebootNotify { desktop = "gnome"; };
    reboot-notify-niri-noctalia = rebootNotify {
      desktop = "niri-noctalia";
      node = {
        # QEMU's virtio-gpu has no 3D acceleration here; without the software
        # KMS driver niri finds no usable renderer and has no outputs, so
        # Noctalia would have no screen to show its bar on.
        systemd.user.services.niri.environment.MESA_LOADER_DRIVER_OVERRIDE = "kms_swrast";
        virtualisation.qemu.options = [ "-vga none -device virtio-gpu-pci" ];
      };
      sessionScript = ''
        noctalia_log = "journalctl _SYSTEMD_USER_UNIT=noctalia-shell.service --no-pager -o cat"

        with subtest("niri uses the central config and has an output"):
            machine.succeed("test ! -e /home/alice/.config/niri/config.kdl")
            machine.wait_until_succeeds(
                "su - alice -c 'NIRI_SOCKET=$(ls /run/user/1000/niri.*.sock) niri msg outputs' | grep -q Virtual-1",
                timeout=60,
            )

        with subtest("Noctalia loads its settings on the first start (fresh home)"):
            machine.wait_until_succeeds(f"{user} is-active noctalia-shell.service", timeout=60)
            machine.wait_until_succeeds(f"{noctalia_log} | grep -q 'Settings loaded'", timeout=120)
            machine.wait_until_succeeds(f"{noctalia_log} | grep -q 'IPCService.*Service started'", timeout=60)
            machine.succeed("test -s /home/alice/.config/noctalia/settings.json")
      '';
      extraScript = ''
        with subtest("the launcher keybinding's IPC call works"):
            # As a niri keybinding runs it: quickshell only targets instances on
            # the caller's Wayland display.
            machine.succeed("su - alice -c 'XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 noctalia-shell ipc call launcher toggle'")
            assert "Shell ID" not in machine.succeed(f"{noctalia_log} --since '-30s'"), "Noctalia restarted"
            machine.succeed(f"{user} is-active noctalia-shell.service")
      '';
    };
  };
}
