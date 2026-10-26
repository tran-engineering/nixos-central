# Profile of kt: the default profile plus the shared modules.
# Personal settings (identity, desktop apps) follow.
{ pkgs, ... }:
let
  font = "FantasqueSansM Nerd Font";
in
{
  imports = [
    ../_default
    ../../modules/home/general-tools.nix
    ../../modules/home/dev-cli
    ../../modules/home/git.nix
    ../../modules/home/jj.nix
    ../../modules/home/fish
    ../../modules/home/zsh.nix
    ../../modules/home/foot.nix
    ../../modules/home/ghostty.nix
    ../../modules/home/dev-desktop.nix
    ../../modules/home/idea.nix
    ../../modules/home/godot.nix
    ../../modules/home/drawio.nix
  ];

  nixos-central.shell = "fish";

  home.shellAliases.ls = "eza";

  home.packages = [ pkgs.nerd-fonts.fantasque-sans-mono ];

  programs.foot.settings.main = {
    include = "${pkgs.foot.themes}/share/foot/themes/kitty";
    term = "kitty";
    font = "${font}:size=14";
  };

  programs.ghostty = {
    settings = {
      font-family = font;
      theme = "dankcolors";
      background-blur-radius = 32;
      unfocused-split-fill = "#44464f";
      gtk-titlebar = false;
    };
    # Generated once by the Dank color tooling; kept static here so the theme
    # survives a fresh checkout.
    themes.dankcolors = {
      background = "#101418";
      foreground = "#e0e2e8";
      cursor-color = "#9dcbfb";
      selection-background = "#124a73";
      selection-foreground = "#e0e2e8";
      palette = [
        "0=#101418"
        "1=#d75a59"
        "2=#8ed88c"
        "3=#e0d99d"
        "4=#4087bc"
        "5=#839fbc"
        "6=#9dcbfb"
        "7=#abb2bf"
        "8=#5c6370"
        "9=#e57e7e"
        "10=#a2e5a0"
        "11=#efe9b3"
        "12=#a7d9ff"
        "13=#3d8197"
        "14=#5c7ba3"
        "15=#ffffff"
      ];
    };
  };
}
