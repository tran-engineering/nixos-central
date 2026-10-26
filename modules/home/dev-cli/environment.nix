# Language tooling environment: binaries installed by cargo and pnpm on the
# PATH, and a global Node.js through mise.
{ lib, ... }:
{
  home.sessionPath = [
    "$HOME/.cargo/bin"
    "$HOME/.local/share/pnpm/bin"
  ];
  home.sessionVariables.PNPM_HOME = lib.mkDefault "$HOME/.local/share/pnpm";

  programs.mise = {
    enable = true;
    globalConfig = {
      tools.node = lib.mkDefault [ "24" ];
      settings.all_compile = lib.mkDefault false;
    };
  };
}
