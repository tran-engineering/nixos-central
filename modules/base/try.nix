# nixos-central-try <branch>: activate this machine's config built against a
# branch of the central repo, without a boot entry and without touching
# /etc/nixos. A reboot returns to the regular configuration.
{
  config,
  pkgs,
  ...
}:
let
  try = pkgs.writeShellApplication {
    name = "nixos-central-try";
    runtimeInputs = [ config.system.build.nixos-rebuild ];
    text = ''
      if [ $# -ne 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        echo "usage: nixos-central-try <branch>" >&2
        echo "Activates ${config.nixos-central.repo} at <branch> until the next reboot." >&2
        exit 2
      fi
      branch=$1

      if [ "$(id -u)" -ne 0 ]; then
        exec sudo "$0" "$@"
      fi

      nixos-rebuild test \
        --flake "/etc/nixos#${config.nixos-central.hostname}" \
        --override-input central "${config.nixos-central.repo}?ref=$branch" \
        --no-write-lock-file \
        --refresh

      echo
      echo "Branch '$branch' is active until the next reboot."
    '';
  };
in
{
  environment.systemPackages = [ try ];
}
