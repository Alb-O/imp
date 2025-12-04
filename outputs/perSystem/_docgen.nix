# Shared documentation generation utilities
{
  pkgs,
  lib,
  nixdoc,
}:
let
  # Use forked nixdoc with let-in identifier resolution and options rendering
  nixdocBin = nixdoc.packages.${pkgs.system}.default;

  # mdformat with plugins
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

  # Write options JSON to a file
  optionsJsonFile = pkgs.writeText "imp-options.json" optionsJson;

  # Script to generate API reference docs
  # Takes $SRC_DIR, $OUT_DIR, $OPTIONS_JSON as arguments
  generateDocsScript = pkgs.writeShellScript "generate-docs" ''
    set -e
    SRC_DIR="$1"
    OUT_DIR="$2"
    OPTIONS_JSON="$3"

    NIXDOC="${lib.getExe' nixdocBin "nixdoc"}"
    MDFORMAT="${lib.getExe mdformat}"

    # Generate methods.md
    {
      echo "# API Methods"
      echo ""
      echo "<!-- Auto-generated from src/*.nix - do not edit -->"
      echo ""
      $NIXDOC \
        --file "$SRC_DIR/api.nix" \
        --category "" \
        --description "" \
        --prefix "imp" \
        --anchor-prefix ""

      echo ""
      echo "## Registry"
      echo ""
      $NIXDOC \
        --file "$SRC_DIR/registry.nix" \
        --category "" \
        --description "" \
        --prefix "imp" \
        --anchor-prefix ""

      echo ""
      echo "## Format Flake"
      echo ""
      $NIXDOC \
        --file "$SRC_DIR/format-flake.nix" \
        --category "" \
        --description "" \
        --prefix "imp" \
        --anchor-prefix ""

      echo ""
      echo "## Analyze"
      echo ""
      $NIXDOC \
        --file "$SRC_DIR/analyze.nix" \
        --category "" \
        --description "" \
        --prefix "imp" \
        --anchor-prefix ""

      echo ""
      echo "## Visualize"
      echo ""
      $NIXDOC \
        --file "$SRC_DIR/visualize.nix" \
        --category "" \
        --description "" \
        --prefix "imp" \
        --anchor-prefix ""

      echo ""
      echo "## Migrate"
      echo ""
      $NIXDOC \
        --file "$SRC_DIR/migrate.nix" \
        --category "" \
        --description "" \
        --prefix "imp" \
        --anchor-prefix ""

      echo ""
      echo "## Standalone Utilities"
      echo ""
      $NIXDOC \
        --file "$SRC_DIR/default.nix" \
        --category "" \
        --description "" \
        --prefix "imp" \
        --anchor-prefix "" \
        --export collectInputs,collectAndFormatFlake
    } > "$OUT_DIR/methods.md"

    # Generate options.md
    $NIXDOC options \
      --file "$OPTIONS_JSON" \
      --title "Module Options" \
      --anchor-prefix "opt-" \
      > "$OUT_DIR/options.md"

    # Generate files.md from file-level doc comments
    {
      echo "# File Reference"
      echo ""
      echo "<!-- Auto-generated from src/*.nix file-level comments - do not edit -->"
      echo ""

      echo "## Core"
      echo ""

      echo "### default.nix"
      echo ""
      $NIXDOC file-doc --file "$SRC_DIR/default.nix" --shift-headings 3 || true
      echo ""

      echo "### api.nix"
      echo ""
      $NIXDOC file-doc --file "$SRC_DIR/api.nix" --shift-headings 3 || true
      echo ""

      echo "### lib.nix"
      echo ""
      echo "Internal utility functions for imp."
      echo ""

      echo "## Import & Collection"
      echo ""

      echo "### collect.nix"
      echo ""
      $NIXDOC file-doc --file "$SRC_DIR/collect.nix" --shift-headings 3 || true
      echo ""

      echo "### tree.nix"
      echo ""
      $NIXDOC file-doc --file "$SRC_DIR/tree.nix" --shift-headings 3 || true
      echo ""

      echo "## Config Trees"
      echo ""

      echo "### configTree.nix"
      echo ""
      $NIXDOC file-doc --file "$SRC_DIR/configTree.nix" --shift-headings 3 || true
      echo ""

      echo "### mergeConfigTrees.nix"
      echo ""
      $NIXDOC file-doc --file "$SRC_DIR/mergeConfigTrees.nix" --shift-headings 3 || true
      echo ""

      echo "## Registry"
      echo ""

      echo "### registry.nix"
      echo ""
      $NIXDOC file-doc --file "$SRC_DIR/registry.nix" --shift-headings 3 || true
      echo ""

      echo "### migrate.nix"
      echo ""
      $NIXDOC file-doc --file "$SRC_DIR/migrate.nix" --shift-headings 3 || true
      echo ""

      echo "### analyze.nix"
      echo ""
      $NIXDOC file-doc --file "$SRC_DIR/analyze.nix" --shift-headings 3 || true
      echo ""

      echo "### visualize.nix"
      echo ""
      $NIXDOC file-doc --file "$SRC_DIR/visualize.nix" --shift-headings 3 || true
      echo ""

      echo "## Flake Integration"
      echo ""

      echo "### flakeModule.nix"
      echo ""
      echo "flake-parts module, defines \`imp.*\` options."
      echo ""

      echo "### collect-inputs.nix"
      echo ""
      echo "\`__inputs\` collection from flake inputs."
      echo ""

      echo "### format-flake.nix"
      echo ""
      $NIXDOC file-doc --file "$SRC_DIR/format-flake.nix" --shift-headings 3 || true
      echo ""
    } > "$OUT_DIR/files.md"

    # Format all generated markdown
    $MDFORMAT "$OUT_DIR/methods.md"
    $MDFORMAT "$OUT_DIR/options.md"
    $MDFORMAT "$OUT_DIR/files.md"
  '';

in
{
  inherit
    nixdocBin
    mdformat
    optionsJson
    optionsJsonFile
    generateDocsScript
    ;
}
