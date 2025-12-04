{
  pkgs,
  lib,
  docgen,
  ...
}:
let
  # Import docgen configuration from docs/
  dg = import ../../docs/docgen.nix { inherit pkgs lib docgen; };
in
{
  # Built documentation site
  docs = dg.docs;

  # Expose API reference for debugging
  api-reference = dg.apiReference;
}
