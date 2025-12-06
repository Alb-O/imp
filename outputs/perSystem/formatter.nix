{
  pkgs,
  treefmt-nix,
  imp-fmt,
  ...
}:
imp-fmt.lib.make {
  inherit pkgs treefmt-nix;
  excludes = [ "tests/fixtures/*" ];
}
