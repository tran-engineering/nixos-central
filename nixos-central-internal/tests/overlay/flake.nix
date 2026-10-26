# Private overlay used by tests: module-only, no inputs (see README, "Private overlay").
# `default` is the fallback profile; `ci-overlay` exists only here (CI selects it
# on a standalone home with `nixos-central-private setup ... --profile ci-overlay`).
{
  outputs = _: rec {
    homeModules.default =
      { centralModules, ... }:
      {
        imports = [ centralModules.fish ];
        home.file.".nixos-central-overlay-test".text = "from the overlay\n";
      };
    homeModules.ci-overlay = {
      imports = [ homeModules.default ];
      home.file.".nixos-central-overlay-profile".text = "ci-overlay\n";
    };
    nixosModules.default = {
      environment.etc."nixos-central-overlay-test".text = "from the overlay\n";
    };
  };
}
