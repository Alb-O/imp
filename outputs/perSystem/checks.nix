{
  self,
  pkgs,
  system,
  nixpkgs,
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
  formatting = formatterEval.config.build.check self;
  nix-unit =
    pkgs.runCommand "nix-unit-tests"
      {
        nativeBuildInputs = [ nix-unit.packages.${system}.default ];
      }
      ''
        export HOME=$TMPDIR
        nix-unit --expr 'import ${self}/tests { lib = import ${nixpkgs}/lib; }'
        touch $out
      '';
}
