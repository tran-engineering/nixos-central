# Help, menu and completion data of the subcommands, shared by the NixOS and
# standalone-home variants. Modules add the `package`:
#   nixos-central.commands.diff = subcommands.diff // { package = ...; };
{
  upgrade = {
    description = "Install the latest update and use it now";
    usage = "[--private]";
    order = 10;
    completions."" = [ "--private" ];
  };
  diff = {
    description = "Show what the pending (or else the last) update changes";
    order = 20;
  };
  status = {
    description = "Show when the last update succeeded";
    order = 30;
    # --if-stale is for the shell hook only; not offered.
  };
  private = {
    description = "Show, add or remove the private overlay";
    usage = "[setup [<flake-url>] [--profile NAME] | remove]";
    order = 40;
    completions = {
      "" = [
        "setup"
        "remove"
      ];
      setup = [ "--profile" ];
    };
  };
  # Not in the menu: it needs a branch.
  try = {
    description = "Use a branch of central until the next reboot";
    usage = "<branch>";
    order = 50;
    chooser = false;
  };
}
