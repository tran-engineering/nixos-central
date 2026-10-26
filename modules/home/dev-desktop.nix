# Shared home module: the Zed editor with its Claude agent. Opt in from a profile with
#   imports = [ ../../modules/home/dev-desktop.nix ];
# Editor settings such as fonts belong in the profile. IntelliJ IDEA, Godot and
# draw.io are separate modules (idea.nix, godot.nix, drawio.nix).
{ pkgs, ... }:
{
  programs.zed-editor = {
    enable = true;
    package = pkgs.unstable.zed-editor;
  };
  home.shellAliases.zed = "zeditor";

  home.packages = [
    pkgs.unstable.claude-agent-acp # Claude agent for Zed (ACP)
  ];
}
