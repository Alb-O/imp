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

  # Use forked nixdoc with let-in identifier resolution
  nixdocBin = nixdoc.packages.${pkgs.system}.default;

  # mdformat with plugins (same as formatter.nix)
  mdformat = pkgs.mdformat.withPlugins (
    ps: with ps; [
      mdformat-gfm
      mdformat-frontmatter
      mdformat-footnote
    ]
  );

  # Standalone utilities section (same as in packages.nix)
  standaloneSection = ''

    ## Standalone Utilities

    These functions work without calling `.withLib` first.

    ### `imp.registry` {#imp.registry}

    Build a registry from a directory structure. Requires `.withLib`.

    #### Example

    ```nix
    registry = (imp.withLib lib).registry ./nix
    # => { hosts.server = <path>; modules.nixos.base = <path>; ... }
    ```

    ### `imp.collectInputs` {#imp.collectInputs}

    Scan directories for `__inputs` declarations and collect them.

    #### Example

    ```nix
    imp.collectInputs ./outputs
    # => { treefmt-nix = { url = "github:numtide/treefmt-nix"; }; }
    ```

    ### `imp.formatFlake` {#imp.formatFlake}

    Format collected inputs as a flake.nix string.

    #### Example

    ```nix
    imp.formatFlake {
      description = "My flake";
      coreInputs = { nixpkgs.url = "github:nixos/nixpkgs"; };
      collectedInputs = imp.collectInputs ./outputs;
    }
    ```

    ### `imp.collectAndFormatFlake` {#imp.collectAndFormatFlake}

    Convenience function combining collectInputs and formatFlake.

    #### Example

    ```nix
    imp.collectAndFormatFlake {
      src = ./outputs;
      coreInputs = { nixpkgs.url = "github:nixos/nixpkgs"; };
      description = "My flake";
    }
    ```
  '';

  # Script to generate API reference (matches packages.nix)
  generateApiRef = pkgs.writeShellScript "generate-api-ref" ''
    set -e
    SITE_DIR="$1"
    SRC_DIR="$2"
    README_FILE="$3"

    # Copy README.md to site/src for Introduction page
    cp "$README_FILE" "$SITE_DIR/src/README.md"

    {
      echo "# API Methods"
      echo ""
      echo "<!-- Auto-generated from src/api.nix - do not edit -->"
      echo ""
      ${lib.getExe' nixdocBin "nixdoc"} \
        --file "$SRC_DIR/api.nix" \
        --category "" \
        --description "" \
        --prefix "imp" \
        --anchor-prefix ""

      echo ""
      echo "## Registry"
      echo ""
      ${lib.getExe' nixdocBin "nixdoc"} \
        --file "$SRC_DIR/registry.nix" \
        --category "" \
        --description "" \
        --prefix "imp" \
        --anchor-prefix ""

      echo ""
      echo "## Format Flake"
      echo ""
      ${lib.getExe' nixdocBin "nixdoc"} \
        --file "$SRC_DIR/format-flake.nix" \
        --category "" \
        --description "" \
        --prefix "imp" \
        --anchor-prefix ""

      echo ""
      echo "## Analyze"
      echo ""
      ${lib.getExe' nixdocBin "nixdoc"} \
        --file "$SRC_DIR/analyze.nix" \
        --category "" \
        --description "" \
        --prefix "imp" \
        --anchor-prefix ""

      echo ""
      echo "## Visualize"
      echo ""
      ${lib.getExe' nixdocBin "nixdoc"} \
        --file "$SRC_DIR/visualize.nix" \
        --category "" \
        --description "" \
        --prefix "imp" \
        --anchor-prefix ""

      cat <<'STANDALONE'
    ${standaloneSection}
    STANDALONE
    } > "$SITE_DIR/src/reference/methods.md"

    # Format the generated markdown
    ${lib.getExe mdformat} "$SITE_DIR/src/reference/methods.md"
  '';
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
        ${generateApiRef} ./site ./src ./README.md

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
    meta.description = "Build the Imp documentation to ./docs";
    program = toString (
      pkgs.writeShellScript "build-docs" ''
        if [ ! -d "./site" ]; then
          echo "Error: ./site directory not found. Run from the imp flake root."
          exit 1
        fi

        echo "Generating API reference from src/*.nix..."
        ${generateApiRef} ./site ./src ./README.md

        ${pkgs.mdbook}/bin/mdbook build ./site --dest-dir "$(pwd)/docs"
        echo "Documentation built to ./docs"
      ''
    );
  };
}
