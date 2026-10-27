# Shared home module: everyday command-line utilities, not specific to
# development. Opt in from a profile with
#   imports = [ ../../modules/home/general-tools.nix ];
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # Downloads and media
    aria2 # better wget
    yt-dlp
    ffmpeg
    imagemagick

    # Files and archives
    p7zip
    bat # better cat
    eza # better ls
    mc # midnight commander
    rsync
    exiftool
    poppler-utils # pdfinfo, pdffonts

    # Disk usage
    dust # better du
    ncdu # du with a TUI

    # Network
    whois
    iftop # network traffic monitor
    dnsutils # nslookup and others

    # Misc
    qrencode
  ];
}
