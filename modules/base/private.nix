# Fetching the private overlay (README, "Private overlay") over SSH without
# interaction: the daily upgrade runs as root, which uses the primary user's
# key for GitHub only. Unconditional, so the first rebuild of
# `nixos-central-private setup` can already fetch the overlay.
{ config, pkgs, ... }:
{
  environment.systemPackages = [ (pkgs.callPackage ../../nixos-central-internal/private { }) ];

  programs.ssh.knownHosts."github.com".publicKey = import ../../nixos-central-internal/lib/github-host-key.nix;

  programs.ssh.extraConfig = ''
    Match host github.com localuser root
      IdentityFile /home/${config.nixos-central.user}/.ssh/id_ed25519
      IdentitiesOnly yes
    # Ends the block, so options other modules append still apply to everyone.
    Match all
  '';
}
