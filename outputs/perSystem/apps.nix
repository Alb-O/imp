{
  pkgs,
  system,
  nix-unit,
  nixpkgs,
  nixdoc,
  self,
  lib,
  ...
}:
let
  visualizeLib = import ../../src/visualize.nix { inherit lib; };

  # Import shared docgen utilities
  docgen = import ./_docgen.nix { inherit pkgs lib nixdoc; };
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
    program = toString (
      pkgs.writeShellScript "serve-docs" ''
        cleanup() { kill $pid 2>/dev/null; }
        trap cleanup EXIT INT TERM
        if [ ! -d "./site" ]; then
          echo "Error: ./site directory not found. Run from the imp flake root."
          exit 1
        fi

        echo "Generating API reference from src/*.nix..."
        mkdir -p ./site/src/reference
        ${docgen.generateDocsScript} ./src ./site/src/reference ${docgen.optionsJsonFile}
        cp ./README.md ./site/src/README.md

        echo "Starting mdbook server..."
        ${pkgs.mdbook}/bin/mdbook serve ./site &
        pid=$!
        sleep 1
        echo "Documentation available at http://localhost:3000"
        wait $pid
      ''
    );
  };

  build-docs = {
    type = "app";
    meta.description = "Build the Imp documentation './site/book' directory.";
    program = toString (
      pkgs.writeShellScript "build-docs" ''
        if [ ! -d "./site" ]; then
          echo "Error: ./site directory not found. Run from the imp flake root."
          exit 1
        fi

        echo "Generating API reference from src/*.nix..."
        mkdir -p ./site/src/reference
        ${docgen.generateDocsScript} ./src ./site/src/reference ${docgen.optionsJsonFile}
        cp ./README.md ./site/src/README.md

        ${pkgs.mdbook}/bin/mdbook build ./site
        echo "Documentation built './site/book' directory."
      ''
    );
  };
}
