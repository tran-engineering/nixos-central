# Imports every desktop module; each one activates itself only when
# nixos-central.desktop matches its file name.
{
  imports = map (name: ./desktops + "/${name}.nix") (import ../nixos-central-internal/lib/desktop-names.nix);
}
