"""End-to-end test of the nixos-central installer in QEMU. See default.nix."""

import argparse
import contextlib
import http.server
import json
import os
import secrets
import re
import shutil
import subprocess
import sys
import threading
import time

import pexpect

PORT = 8000
HOST_IP = "10.0.2.2"  # the host as seen from QEMU user networking
CENTRAL_URL = f"git+http://{HOST_IP}:{PORT}/cgi-bin/git/central.git"
PRIVATE_URL = f"git+http://{HOST_IP}:{PORT}/cgi-bin/git/private.git"
# Generated per run (see main) so they cannot occur in any source file that
# ends up in the installed Nix store.
LUKS = ""
PASSWORD = ""
SHELL_PROMPT = r"\]\$(?:\x1b\[0m)? "  # NixOS PS1: "[user@host:dir]$ " with colours


def log(msg):
    print(f"\n\033[1;34m### {msg}\033[0m", flush=True)


def check(cond, msg):
    if not cond:
        raise AssertionError(msg)
    print(f"\033[32mOK\033[0m {msg}", flush=True)


def desktop_names(repo):
    """Desktops the installer offers: modules/desktops/<name>.nix, sorted like lib.desktopNames."""
    return sorted(f[:-4] for f in os.listdir(os.path.join(repo, "modules", "desktops")) if f.endswith(".nix"))


class Repo:
    """Bare copy of the working tree, served over smart HTTP via git http-backend."""

    def __init__(self, src, state):
        self.www = os.path.join(state, "www")
        self.bare = os.path.join(self.www, "repos", "central.git")
        self.work = os.path.join(state, "central-work")
        shutil.rmtree(self.www, ignore_errors=True)
        shutil.rmtree(self.work, ignore_errors=True)
        os.makedirs(os.path.join(self.www, "cgi-bin"))
        subprocess.run(
            ["rsync", "-a", "--exclude=.git", "--exclude=.vm*", "--exclude=result*", f"{src}/", f"{self.work}/"],
            check=True,
        )
        # try/update in the VM must reach this server instead of GitHub
        opts = os.path.join(self.work, "modules", "options.nix")
        text = open(opts).read().replace('"git+https://github.com/tran-engineering/nixos-central"', f'"{CENTRAL_URL}"')
        open(opts, "w").write(text)
        self.git("init", "-q", "-b", "main")
        self.commit("initial")
        subprocess.run(["git", "clone", "-q", "--bare", self.work, self.bare], check=True)
        self.git("remote", "add", "origin", self.bare)
        cgi = os.path.join(self.www, "cgi-bin", "git")
        with open(cgi, "w") as f:
            f.write(
                "#!/bin/sh\n"
                f"export GIT_PROJECT_ROOT={os.path.join(self.www, 'repos')} GIT_HTTP_EXPORT_ALL=1\n"
                f"exec {shutil.which('git')} http-backend\n"
            )
        os.chmod(cgi, 0o755)
        shutil.copy(
            os.path.join(src, "nixos-central-internal", "installer", "install.sh"),
            os.path.join(self.www, "install.sh"),
        )

    def git(self, *args):
        subprocess.run(["git", "-C", self.work, "-c", "user.name=e2e", "-c", "user.email=e2e@test", *args], check=True)

    def commit(self, msg):
        self.git("add", "-A")
        self.git("commit", "-q", "-m", msg)

    def write(self, path, text):
        full = os.path.join(self.work, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w") as f:
            f.write(text)

    def private_overlay(self, marker):
        """(Re)write the served private overlay: a module-only flake placing ~/overlay-marker."""
        work = os.path.join(os.path.dirname(self.work), "private-work")
        bare = os.path.join(self.www, "repos", "private.git")
        git = ["git", "-C", work, "-c", "user.name=e2e", "-c", "user.email=e2e@test"]
        first = not os.path.isdir(work)
        os.makedirs(work, exist_ok=True)
        with open(os.path.join(work, "flake.nix"), "w") as f:
            f.write(
                "{ outputs = _: { homeModules.default = { centralModules, ... }: {\n"
                "  imports = [ centralModules.zsh ];\n"
                f'  home.file.overlay-marker.text = "{marker}";\n'
                "}; }; }\n"
            )
        if first:
            subprocess.run([*git, "init", "-q", "-b", "main"], check=True)
        subprocess.run([*git, "add", "-A"], check=True)
        subprocess.run([*git, "commit", "-q", "-m", marker], check=True)
        if first:
            shutil.rmtree(bare, ignore_errors=True)
            subprocess.run(["git", "clone", "-q", "--bare", work, bare], check=True)
            subprocess.run([*git, "remote", "add", "origin", bare], check=True)
        else:
            subprocess.run([*git, "push", "-q", "origin", "main"], check=True)

    def serve(self):
        www = self.www

        class Handler(http.server.CGIHTTPRequestHandler):
            def __init__(self, *a, **kw):
                super().__init__(*a, directory=www, **kw)

            def log_message(self, *a):
                pass

        server = http.server.ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        return server


class VM:
    def __init__(self, args, iso=None, usb=True, uefi=True):
        state = args.state
        cmd = [
            "qemu-system-x86_64", "-enable-kvm", "-machine", "q35", "-cpu", "host",
            "-m", "6144", "-smp", "4", "-nographic",
            "-drive", f"file={state}/internal.qcow2,if=virtio,format=qcow2",
            "-nic", "user,model=virtio-net-pci",
        ]
        if uefi:
            cmd += [
                "-drive", f"if=pflash,format=raw,readonly=on,file={args.ovmf}/OVMF_CODE.fd",
                "-drive", f"if=pflash,format=raw,file={state}/vars.fd",
            ]
        if usb:
            cmd += [
                "-device", "qemu-xhci",
                "-drive", f"if=none,id=usbdisk,file={state}/usb.qcow2,format=qcow2",
                "-device", "usb-storage,drive=usbdisk",
            ]
        if iso:
            cmd += ["-cdrom", iso, "-boot", "order=d"]
        logfile = open(os.path.join(state, "serial.log"), "a")
        self.p = pexpect.spawn(cmd[0], cmd[1:], encoding="utf-8", codec_errors="replace", timeout=300)
        self.p.logfile_read = _Tee(logfile)

    def expect(self, pattern, timeout=300):
        return self.p.expect(pattern, timeout=timeout)

    def send(self, line):
        self.p.sendline(line)

    def answer(self, prompt, line, timeout=300):
        self.expect(prompt, timeout)
        time.sleep(0.3)
        self.send(line)

    def run(self, command, timeout=600, prompt=SHELL_PROMPT):
        """Run a shell command, return (exit code, output)."""
        marker = f"__RC{int(time.time() * 1000) % 100000}__"
        self.send(f"{command}; echo {marker}$?")
        self.expect(re.escape(marker) + r"(\d+)", timeout)
        out = self.p.before
        rc = int(self.p.match.group(1))
        self.expect(prompt, 30)
        return rc, out

    def succeed(self, command, timeout=600, **kw):
        rc, out = self.run(command, timeout, **kw)
        if rc != 0:
            raise AssertionError(f"command failed ({rc}): {command}\n{out}")
        return out

    def quiet(self):
        """No line editing and no echo, so command output can be parsed."""
        self.send("exec bash --noediting")
        self.expect(SHELL_PROMPT, 30)
        self.send("stty -echo; export TERM=dumb")
        self.expect(SHELL_PROMPT, 30)

    def poweroff(self):
        self.send("sudo poweroff")
        # the live image has passwordless sudo, the installed system does not
        if self.p.expect([r"\[sudo\] password for \w+: ", pexpect.EOF], timeout=180) == 0:
            self.send(PASSWORD)
            self.p.expect(pexpect.EOF, timeout=180)


class _Tee:
    def __init__(self, f):
        self.f = f

    def write(self, s):
        self.f.write(s)
        sys.stdout.write(s)

    def flush(self):
        self.f.flush()
        sys.stdout.flush()


def make_disks(args, internal="50G"):
    os.makedirs(args.state, exist_ok=True)
    for name, size in [("internal", internal), ("usb", "64G")]:
        path = os.path.join(args.state, f"{name}.qcow2")
        with contextlib.suppress(FileNotFoundError):
            os.remove(path)
        subprocess.run(["qemu-img", "create", "-q", "-f", "qcow2", path, size], check=True)
    shutil.copy(os.path.join(args.ovmf, "OVMF_VARS.fd"), os.path.join(args.state, "vars.fd"))
    os.chmod(os.path.join(args.state, "vars.fd"), 0o644)


RUN_INSTALLER = f"curl -sL http://{HOST_IP}:{PORT}/install.sh | NIXOS_CENTRAL_FLAKE={CENTRAL_URL} sh"


def live_vm(args, **kw):
    vm = VM(args, iso=args.iso, **kw)
    vm.expect(r"nixos@nixos.*" + SHELL_PROMPT, 600)
    vm.quiet()
    return vm


def phase_variants(args):
    """Failure paths and the reuse-passphrase install (tasks 5.2, 5.4, 5.5)."""
    flags = "-s -- --hostname variant --user alice --desktop none"

    log("preflight: legacy BIOS boot is refused")
    make_disks(args)
    vm = live_vm(args, uefi=False, usb=False)
    vm.send(RUN_INSTALLER)
    vm.expect(r"legacy BIOS mode\. Restart and boot the USB image in UEFI mode", 300)
    vm.expect(SHELL_PROMPT)
    check("EMPTY" in vm.succeed("sudo blkid /dev/vda || echo EMPTY"), "BIOS boot: aborted, disk untouched")
    vm.poweroff()

    log("disk: only a 32 GiB internal disk (plus USB) is refused with a list")
    make_disks(args, internal="32G")
    vm = live_vm(args)
    vm.send(f"{RUN_INSTALLER} {flags}")
    vm.expect(r"Disks found:", 900)
    vm.expect(r"/dev/vda\s+32G")
    vm.expect(r"No internal disk of at least 40 GiB found")
    vm.expect(SHELL_PROMPT)
    check(True, "32 GiB disk: aborted and listed the disks")
    check("EMPTY" in vm.succeed("sudo blkid /dev/vda || echo EMPTY"), "small disk untouched")

    log("preflight: no network")
    vm.succeed(f"curl -sLo /tmp/install.sh http://{HOST_IP}:{PORT}/install.sh && sudo nmcli networking off")
    vm.send(f"NIXOS_CENTRAL_FLAKE={CENTRAL_URL} sh /tmp/install.sh {flags.removeprefix('-s -- ')}")
    vm.expect(r"No connection to github\.com\. Connect to the network first \(Wi-Fi: run 'nmtui'\)", 120)
    vm.expect(SHELL_PROMPT)
    check(True, "no network: aborted with nmtui hint")
    vm.poweroff()

    log("install reusing the disk passphrase as login password")
    make_disks(args)
    vm = live_vm(args)
    vm.send(f"{RUN_INSTALLER} {flags}")
    vm.answer(r"Type 'yes' to erase it and install: ", "yes", 900)
    vm.answer(r"Disk passphrase: ", LUKS)
    vm.answer(r"Repeat to confirm: ", LUKS)
    vm.answer(r"login password for alice too\? \[Y/n\]: ", "")
    vm.answer(r"Reboot now\? \[Y/n\]: ", "n", 7200)
    vm.expect(SHELL_PROMPT)
    rc, _ = vm.run(
        "h=$(sudo cat /mnt/etc/secrets/alice.hash); salt=$(echo \"$h\" | cut -d'$' -f3); "
        "ossl() { if command -v openssl >/dev/null; then openssl \"$@\"; else nix --extra-experimental-features 'nix-command flakes' run nixpkgs#openssl -- \"$@\"; fi; }; "
        f"[ \"$(printf %s {LUKS} | ossl passwd -6 -salt \"$salt\" -stdin)\" = \"$h\" ]",
    )
    check(rc == 0, "login password hash matches the disk passphrase")
    vm.poweroff()


def phase_install(args):
    vm = live_vm(args)
    run_installer = RUN_INSTALLER

    log("installer: prompts, validation, auto-selected disk, declined wipe")
    vm.send(run_installer)
    vm.answer(r"Hostname \[nixos-[a-z0-9]{4}\]: ", "Bad_Host", 900)
    vm.answer(r"lowercase letters.*\r\n.*Hostname \[nixos-[a-z0-9]{4}\]: ", "e2e-host")
    vm.answer(r"Your username: ", "Alice Smith")
    vm.answer(r"reserved.*\r\n.*Your username: ", "root")
    vm.answer(r"reserved.*\r\n.*Your username: ", "alice")
    vm.answer(r"Desktop \[kde\]: ", "windows")
    desktops = re.escape(" ".join(desktop_names(args.repo)))
    vm.answer(rf"Choose one of: {desktops}.*\r\n.*Desktop \[kde\]: ", "none")
    vm.expect(r"NixOS will be installed on:\s+/dev/vda \(50G")
    check(True, "first internal disk /dev/vda chosen, USB disk /dev/sda (64G) skipped")
    vm.answer(r"Type 'yes' to erase it and install: ", "y")
    vm.expect(r"Aborted\. Nothing was changed\.")
    vm.expect(SHELL_PROMPT)
    out = vm.succeed("sudo blkid /dev/vda || echo EMPTY")
    check("EMPTY" in out, "declined wipe left /dev/vda untouched")

    log("installer: flags, typed confirmation, secrets, install")
    vm.send(f"{run_installer} -s -- --hostname e2e-host --user alice --desktop none")
    vm.answer(r"Type 'yes' to erase it and install: ", "yes", 900)
    vm.answer(r"Disk passphrase: ", LUKS)
    vm.answer(r"Repeat to confirm: ", "mismatch")
    vm.answer(r"did not match.*\r\n.*Disk passphrase: ", LUKS)
    vm.answer(r"Repeat to confirm: ", LUKS)
    vm.answer(r"login password for alice too\? \[Y/n\]: ", "n")
    vm.answer(r"Login password for alice: ", PASSWORD)
    vm.answer(r"Repeat to confirm: ", PASSWORD)
    vm.answer(r"Reboot now\? \[Y/n\]: ", "n", 7200)
    vm.expect(SHELL_PROMPT)

    out = vm.succeed("sudo ls /mnt/etc/nixos")
    check(all(f in out for f in ["flake.nix", "flake.lock", "hardware-configuration.nix"]), "/mnt/etc/nixos has flake, lock, hardware config")
    out = vm.succeed("sudo stat -c '%a %U' /mnt/etc/secrets/alice.hash")
    check("400 root" in out, "password hash stored 0400 root outside the store")
    rc, _ = vm.run("test -e /tmp/nixos-central-luks.key")
    check(rc != 0, "LUKS key file removed from the live image")
    rc, _ = vm.run(f"grep -F -q -e {LUKS} -e {PASSWORD} /tmp/nixos-central-install.log")
    check(rc != 0, "no secret in the install log")
    rc, _ = vm.run(f"sudo grep -r -F -l -q -e {LUKS} -e {PASSWORD} -e \"$(sudo cat /mnt/etc/secrets/alice.hash)\" /mnt/nix/store", 1800)
    check(rc != 0, "no passphrase, password or hash in the installed Nix store")

    log("test only: serial console on the installed system")
    vm.succeed(
        "sudo sed -i 's|^}$|  boot.kernelParams = [ \"console=ttyS0,115200\" ];\\n}|' /mnt/etc/nixos/hardware-configuration.nix"
        " && sudo nixos-install --root /mnt --flake /mnt/etc/nixos#e2e-host --no-root-passwd --no-channel-copy",
        3600,
    )
    vm.poweroff()


def boot_installed(args):
    vm = VM(args, usb=False)
    vm.answer(r"(?i)passphrase for", LUKS, 600)
    vm.answer(r"e2e-host login: ", "alice", 600)
    vm.answer(r"Password: ", PASSWORD)
    vm.expect(SHELL_PROMPT, 120)
    vm.quiet()
    return vm


def sudo(vm, command, timeout=600):
    """Run a command with sudo, answering its password prompt."""
    marker = f"__RC{int(time.time() * 1000) % 100000}__"
    vm.send(f"sudo -k; sudo sh -c '{command}'; echo {marker}$?")
    vm.answer(r"\[sudo\] password for alice: ", PASSWORD)
    vm.expect(re.escape(marker) + r"(\d+)", timeout)
    out, rc = vm.p.before, int(vm.p.match.group(1))
    vm.expect(SHELL_PROMPT, 30)
    return rc, out


def boot_entries(vm):
    """Number of systemd-boot entries (/boot is root-only)."""
    rc, out = sudo(vm, "ls /boot/loader/entries | wc -l")
    assert rc == 0, out
    return int(out.split()[-1])


def phase_installed(args, repo):
    log("installed system: LUKS, login, sudo, facts")
    vm = boot_installed(args)
    check("e2e-host" in vm.succeed("hostname"), "hostname is e2e-host")
    rc, _ = sudo(vm, "true")
    check(rc == 0, "primary user can sudo with the chosen password")
    out = vm.succeed("ls /etc/nixos")
    check(out.split()[-3:] == ["flake.lock", "flake.nix", "hardware-configuration.nix"], "/etc/nixos holds only flake, lock, hardware config")
    rc, _ = vm.run("systemctl is-active display-manager")
    check(rc != 0, "desktop 'none': no display manager")
    check("Hello, world!" in vm.succeed("nix-shell -p hello --run hello", 900), "nix-shell -p works")
    check("vim" in vm.succeed("echo $EDITOR"), "no users/alice yet: default profile (EDITOR=vim)")

    log("auto-upgrade: personal profile merged later is staged for next boot")
    repo.write("users/alice/default.nix", '{ lib, ... }: {\n  imports = [ ../_default ];\n  home.sessionVariables.EDITOR = lib.mkForce "nano";\n}\n')
    repo.commit("add alice profile")
    repo.git("push", "-q", "origin", "main")
    before = vm.succeed("readlink /run/current-system; md5sum /etc/nixos/flake.lock").split() + [boot_entries(vm)]
    rc, out = sudo(vm, "systemctl start nixos-upgrade.service", 3600)
    check(rc == 0, "nixos-upgrade.service succeeded")
    after = vm.succeed("readlink /run/current-system; md5sum /etc/nixos/flake.lock").split() + [boot_entries(vm)]
    check(before[0] == after[0], "running system unchanged by the upgrade")
    check(before[1] != after[1], "flake.lock updated (central bumped)")
    check(after[-1] == before[-1] + 1, f"new boot entry added ({before[-1]} -> {after[-1]})")
    staged = vm.succeed("readlink -f /nix/var/nix/profiles/system").split()[-1]

    log("nixos-central-try: branch active now, lock untouched, no boot entry")
    repo.git("checkout", "-q", "-b", "alice-wip")
    repo.write("users/alice/default.nix", '{ lib, ... }: {\n  imports = [ ../_default ];\n  home.sessionVariables.EDITOR = lib.mkForce "nano";\n  home.file.try-marker.text = "wip";\n}\n')
    repo.commit("wip")
    repo.git("push", "-q", "origin", "alice-wip")
    repo.git("checkout", "-q", "main")
    lock = vm.succeed("md5sum /etc/nixos/flake.lock").split() + [boot_entries(vm)]
    vm.send("sudo -k")
    vm.expect(SHELL_PROMPT)
    vm.send("nixos-central-try alice-wip; echo __TRY$?")
    vm.answer(r"\[sudo\] password for alice: ", PASSWORD)
    vm.expect(r"__TRY(\d+)", 3600)
    check(vm.p.match.group(1) == "0", "nixos-central-try alice-wip succeeded")
    vm.expect(SHELL_PROMPT)
    check("wip" in vm.succeed("cat ~/try-marker"), "branch change active")
    check(vm.succeed("md5sum /etc/nixos/flake.lock").split() + [boot_entries(vm)] == lock, "flake.lock and boot entries unchanged by try")
    rc, out = sudo(vm, "nixos-central-try no-such-branch", 900)
    check(rc != 0, "nixos-central-try with a missing branch fails")
    vm.poweroff()

    log("reboot: try reverted, staged update active")
    vm = boot_installed(args)
    rc, _ = vm.run("test -e ~/try-marker")
    check(rc != 0, "try change gone after reboot")
    check(vm.succeed("readlink -f /run/booted-system").split()[-1] == staged, "booted the staged generation")
    check("nano" in vm.succeed("bash -lc 'echo $EDITOR'"), "personal profile users/alice active")

    log("nixos-central-upgrade: latest main active right away and after reboot, ends a tried branch")
    vm.send("sudo -k")
    vm.expect(SHELL_PROMPT)
    vm.send("nixos-central-try alice-wip; echo __TRY$?")
    vm.answer(r"\[sudo\] password for alice: ", PASSWORD)
    vm.expect(r"__TRY(\d+)", 3600)
    check(vm.p.match.group(1) == "0", "nixos-central-try alice-wip succeeded")
    vm.expect(SHELL_PROMPT)
    repo.write("users/alice/default.nix", '{ lib, ... }: {\n  imports = [ ../_default ];\n  home.sessionVariables.EDITOR = lib.mkForce "nano";\n  home.file.upgrade-marker.text = "upgraded";\n}\n')
    repo.commit("alice: upgrade marker")
    repo.git("push", "-q", "origin", "main")
    before = vm.succeed("md5sum /etc/nixos/flake.lock").split() + [boot_entries(vm)]
    vm.send("sudo -k")
    vm.expect(SHELL_PROMPT)
    vm.send("nixos-central-upgrade; echo __UP$?")
    vm.answer(r"\[sudo\] password for alice: ", PASSWORD)
    vm.expect(r"__UP(\d+)", 3600)
    out, rc = vm.p.before, vm.p.match.group(1)
    check(rc == "0", "nixos-central-upgrade succeeded")
    check("new kernel" not in out, "no kernel hint when the kernel did not change")
    vm.expect(SHELL_PROMPT)
    check("upgraded" in vm.succeed("cat ~/upgrade-marker"), "upgrade active immediately")
    rc, _ = vm.run("test -e ~/try-marker")
    check(rc != 0, "tried branch replaced by main")
    after = vm.succeed("md5sum /etc/nixos/flake.lock").split() + [boot_entries(vm)]
    check(before[0] != after[0], "flake.lock updated (central bumped)")
    check(after[-1] == before[-1] + 1, f"new boot entry added ({before[-1]} -> {after[-1]})")
    switched = vm.succeed("readlink -f /nix/var/nix/profiles/system").split()[-1]
    check(vm.succeed("readlink -f /run/current-system").split()[-1] == switched, "default boot entry is the running system")
    vm.poweroff()

    log("reboot: upgrade persists")
    vm = boot_installed(args)
    check("upgraded" in vm.succeed("cat ~/upgrade-marker"), "upgrade still active after reboot")
    check(vm.succeed("readlink -f /run/booted-system").split()[-1] == switched, "booted the upgraded generation")

    log("private overlay: setup, upgrade with a new overlay commit, remove")
    shutil.rmtree(os.path.join(os.path.dirname(repo.work), "private-work"), ignore_errors=True)
    repo.private_overlay("v1")
    rc, out = sudo(vm, f"nixos-central-private setup {PRIVATE_URL}", 3600)
    check(rc == 0, "nixos-central-private setup succeeded")
    flake = vm.succeed("cat /etc/nixos/flake.nix")
    check(f'inputs.private.url = "{PRIVATE_URL}";' in flake and "inherit private;" in flake, "overlay declared in /etc/nixos/flake.nix")
    check("v1" in vm.succeed("cat ~/overlay-marker"), "overlay's file active")
    check("zsh-autosuggestions" in vm.succeed("cat ~/.zshrc"), "overlay picked a shared module via centralModules")
    repo.private_overlay("v2")
    rc, out = sudo(vm, "nixos-central-upgrade", 3600)
    check(rc == 0, "nixos-central-upgrade with overlay succeeded")
    check("v2" in vm.succeed("cat ~/overlay-marker"), "new overlay commit active after upgrade")
    rc, out = sudo(vm, "nixos-central-private remove", 3600)
    check(rc == 0, "nixos-central-private remove succeeded")
    check("private" not in vm.succeed("cat /etc/nixos/flake.nix"), "overlay gone from /etc/nixos/flake.nix")
    rc, _ = vm.run("test -e ~/overlay-marker")
    check(rc != 0, "overlay's file removed")
    vm.poweroff()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--iso", required=True)
    ap.add_argument("--ovmf", required=True)
    ap.add_argument("--state", default=None)
    ap.add_argument("--skip-install", action="store_true", help="reuse the installed disk from a previous run")
    ap.add_argument("--variants", action="store_true", help="run failure paths and the reuse-passphrase install instead")
    args = ap.parse_args()
    args.state = args.state or os.path.join(args.repo, ".vm")

    global LUKS, PASSWORD
    secrets_file = os.path.join(args.state, "secrets.json")
    if args.skip_install:
        LUKS, PASSWORD = json.load(open(secrets_file))
    else:
        os.makedirs(args.state, exist_ok=True)
        LUKS, PASSWORD = f"luks-{secrets.token_hex(8)}", f"pw-{secrets.token_hex(8)}"
        json.dump([LUKS, PASSWORD], open(secrets_file, "w"))

    repo = Repo(args.repo, args.state) if not args.skip_install else None
    if repo is None:
        repo = Repo.__new__(Repo)
        repo.www = os.path.join(args.state, "www")
        repo.bare = os.path.join(repo.www, "repos", "central.git")
        repo.work = os.path.join(args.state, "central-work")
    server = repo.serve()
    try:
        if args.variants:
            phase_variants(args)
            log("ALL VARIANT CHECKS PASSED")
            return
        if not args.skip_install:
            make_disks(args)
            phase_install(args)
        phase_installed(args, repo)
    finally:
        server.shutdown()
    log("ALL END-TO-END CHECKS PASSED")


if __name__ == "__main__":
    main()
