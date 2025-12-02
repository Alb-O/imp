/*
  Builds flake outputs from directory structure with automatic per-system handling.

  Detection: files accepting `pkgs` or `system` are wrapped with lib.genAttrs,
  other files are called directly with base args.

  Example structure:
    outputs/
      packages.nix      -> { pkgs, ... }: { hello = pkgs.hello; }  (per-system)
      devShells.nix     -> { pkgs, ... }: { default = ...; }       (per-system)
      nixosConfigurations/
        server.nix      -> { lib, ... }: lib.nixosSystem { ... }   (direct)

  Usage:

    (imp.withLib lib).flakeOutputs {
      systems = [ "x86_64-linux" "aarch64-linux" ];
      pkgsFor = system: nixpkgs.legacyPackages.''${system};
      args = { inherit self lib inputs; };
    } ./outputs

  Parameters:
    - systems: List of systems to generate (e.g., flake-utils.lib.defaultSystems)
    - pkgsFor: Function `system -> pkgs` to get nixpkgs for each system
    - args: Base arguments passed to all files (per-system files also get pkgs and system)

  Per-system files (accepting pkgs or system):

    # outputs/packages.nix
    { pkgs, ... }: {
      hello = pkgs.hello;
    }
    # Result: packages.x86_64-linux.hello, packages.aarch64-linux.hello, ...

  System-independent files (no pkgs/system arg):

    # outputs/nixosConfigurations/server.nix
    { lib, ... }:
    lib.nixosSystem { system = "x86_64-linux"; modules = [ ... ]; }
    # Result: nixosConfigurations.server (direct value, not per-system)
*/
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
