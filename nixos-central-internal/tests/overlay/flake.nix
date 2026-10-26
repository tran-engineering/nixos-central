# Private overlay used by tests: module-only, no inputs (see README, "Private overlay").
{
  outputs = _: {
    homeModules.default =
      { centralModules, ... }:
      {
        imports = [ centralModules.fish ];
        home.file.".nixos-central-overlay-test".text = "from the overlay\n";
      };
    nixosModules.default = {
      environment.etc."nixos-central-overlay-test".text = "from the overlay\n";
    };
  };
}
