# Builds flake outputs from directory structure with automatic per-system handling.
#
# Detection: files accepting `pkgs` or `system` are wrapped with lib.genAttrs,
# other files are called directly with base args.
#
# Example structure:
#   outputs/
#     packages.nix      -> { pkgs, ... }: { hello = pkgs.hello; }  (per-system)
#     devShells.nix     -> { pkgs, ... }: { default = ...; }       (per-system)
#     nixosConfigurations/
#       server.nix      -> { lib, ... }: lib.nixosSystem { ... }   (direct)
{
  lib,
  systems,
  pkgsFor,
  args,
  treef ? import,
  filterf ? _: true,
}:
let
  wantsPerSystem =
    f:
    let
      fArgs = builtins.functionArgs f;
    in
    fArgs ? pkgs || fArgs ? system;

  wrapPerSystem =
    f:
    lib.genAttrs systems (
      system:
      f (
        args
        // {
          inherit system;
          pkgs = pkgsFor system;
        }
      )
    );

  processImport =
    imported:
    let
      f = if builtins.isFunction imported then imported else (_: imported);
      needsPerSystem = builtins.isFunction imported && wantsPerSystem imported;
    in
    if needsPerSystem then wrapPerSystem f else f args;

  buildTree = import ./tree.nix {
    inherit lib filterf;
    treef = path: processImport (treef path);
  };
in
buildTree
