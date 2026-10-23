# Shared default profile (home-manager module) for every user without a
# personal profile in users/<name>. Personal profiles can reuse it with
#   imports = [ ../_default ];
{ pkgs, ... }:
{
  programs.bash.enable = true;

  programs.git = {
    enable = true;
    settings.init.defaultBranch = "main";
  };

  programs.firefox.enable = true;

  home.packages = with pkgs; [
    vim
    htop
    wget
    unzip
  ];

  home.sessionVariables.EDITOR = "vim";
}
