{
  pkgs,
  system,
  nix-unit,
  nixpkgs,
  docgen,
  imp-graph,
  self,
  lib,
  ...
}:
let
  # Import docgen configuration from docs/
  dg = import ../../docs/docgen.nix { inherit pkgs lib docgen; };

  # WASM distribution for visualization
  wasmDistPath = imp-graph.packages.${system}.default;
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
      imp-graph.lib.mkVisualizeScript {
        inherit pkgs wasmDistPath;
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
