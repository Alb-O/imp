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

  # Use forked nixdoc with let-in identifier resolution and options rendering
  nixdocBin = nixdoc.packages.${pkgs.system}.default;

  # mdformat with plugins (same as formatter.nix)
  mdformat = pkgs.mdformat.withPlugins (
    ps: with ps; [
      mdformat-gfm
      mdformat-frontmatter
      mdformat-footnote
    ]
  );

  # Use shared options schema for documentation generation
  optionsSchema = import ../../src/options-schema.nix { inherit lib; };

  # Evaluate module to get properly structured options
  evaluatedModule = lib.evalModules {
    modules = [ optionsSchema ];
  };

  # Extract options to JSON
  rawOpts = lib.optionAttrSetToDocList evaluatedModule.options;
  filteredOpts = lib.filter (
    opt: (opt.visible or true) && !(opt.internal or false) && lib.hasPrefix "imp." opt.name
  ) rawOpts;
  optionsNix = builtins.listToAttrs (
    map (o: {
      name = o.name;
      value = removeAttrs o [
        "name"
        "visible"
        "internal"
      ];
    }) filteredOpts
  );
  optionsJson = builtins.toJSON optionsNix;

  # Write options JSON to a file for the shell scripts
  optionsJsonFile = pkgs.writeText "imp-options.json" optionsJson;

  # Script to generate API reference (uses nixdoc for both methods and options)
  generateApiRef = pkgs.writeShellScript "generate-api-ref" ''
    set -e
    SITE_DIR="$1"
    SRC_DIR="$2"
    README_FILE="$3"
    OPTIONS_JSON="$4"

    # Copy README.md to site/src for Introduction page
    cp "$README_FILE" "$SITE_DIR/src/README.md"

    {
      echo "# API Methods"
      echo ""
      echo "<!-- Auto-generated from src/*.nix - do not edit -->"
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

      echo ""
      echo "## Standalone Utilities"
      echo ""
      ${lib.getExe' nixdocBin "nixdoc"} \
        --file "$SRC_DIR/standalone.nix" \
        --category "" \
        --description "" \
        --prefix "imp" \
        --anchor-prefix ""
    } > "$SITE_DIR/src/reference/methods.md"

    # Generate options using nixdoc options command
    ${lib.getExe' nixdocBin "nixdoc"} options \
      --file "$OPTIONS_JSON" \
      --title "Module Options" \
      --anchor-prefix "opt-" \
      > "$SITE_DIR/src/reference/options.md"

    # Format the generated markdown
    ${lib.getExe mdformat} "$SITE_DIR/src/reference/methods.md"
    ${lib.getExe mdformat} "$SITE_DIR/src/reference/options.md"
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
        ${generateApiRef} ./site ./src ./README.md ${optionsJsonFile}

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
        ${generateApiRef} ./site ./src ./README.md ${optionsJsonFile}

        ${pkgs.mdbook}/bin/mdbook build ./site --dest-dir "$(pwd)/docs"
        echo "Documentation built to ./docs"
      ''
    );
  };
}
