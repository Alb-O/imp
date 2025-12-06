{
  pkgs,
  treefmt-nix,
  ...
}:
let
  formatterLib = import ../../src/formatter;
in
formatterLib.make {
  inherit pkgs treefmt-nix;
  excludes = [ "tests/fixtures/*" ];
}
