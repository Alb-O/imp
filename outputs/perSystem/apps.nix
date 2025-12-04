{
  pkgs,
  system,
  nix-unit,
  nixpkgs,
  docgen,
  self,
  lib,
  ...
}:
let
  visualizeLib = import ../../src/visualize { inherit lib; };

  # Import docgen configuration from docs/
  dg = import ../../docs/docgen.nix { inherit pkgs lib docgen; };
in
{
  tests = {
    type = "app";
    meta.description = "Run imp unit tests";
    program = toString (
      pkgs.writeShellScript "run-tests" ''
        ${nix-unit.packages.${system}.default}/bin/nix-unit --flake .#tests
      ''
    );
  };

  /**
    Visualize registry dependencies as an interactive HTML graph.

    Usage:
      nix run .#visualize -- <path-to-nix-directory>

    Examples:
      nix run .#visualize -- ./nix > deps.html

    The tool scans the directory for a registry structure and analyzes
    all modules for cross-references.
  */
  visualize = {
    type = "app";
    meta.description = "Visualize imp registry dependencies (standalone)";
    program = toString (
      visualizeLib.mkVisualizeScript {
        inherit pkgs;
        impSrc = self.sourceInfo or self;
        nixpkgsFlake = nixpkgs;
        name = "imp-vis";
      }
    );
  };

  docs = {
    type = "app";
    meta.description = "Serve the Imp documentation locally with live reload";
    program = toString dg.serveDocsScript;
  };

  build-docs = {
    type = "app";
    meta.description = "Build the Imp documentation to './docs/book' directory.";
    program = toString dg.buildDocsScript;
  };
}
