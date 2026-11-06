# Shared home module: everyday command-line utilities, not specific to
# development. Opt in from a profile with
#   imports = [ ../../modules/home/general-tools.nix ];
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # Files
    rsync

    # Disk usage
    dust # better du
    ncdu # du with a TUI

    # Network
    whois
    iftop # network traffic monitor
    dnsutils # nslookup and others
  ];
}
