# Unit tests for imp
{ lib }:
let
  imp = import ./../src;
  args = { inherit lib imp; };
in
(import ./core.nix args)
// (import ./imp.nix args)
// (import ./tree.nix args)
// (import ./flake-file.nix args)
// (import ./registry.nix args)
// (import ./migrate.nix args)
// (import ./analyze.nix args)
