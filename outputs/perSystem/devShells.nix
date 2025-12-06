{
  pkgs,
  system,
  nix-unit,
  treefmt-nix,
  imp-fmt,
  ...
}:
let
  formatterEval = imp-fmt.lib.makeEval {
    inherit pkgs treefmt-nix;
    excludes = [ "tests/fixtures/*" ];
  };
in
{
  default = pkgs.mkShell {
    packages = [
      nix-unit.packages.${system}.default
    ];
    inputsFrom = [ formatterEval.config.build.devShell ];
  };
}
