# Documentation generation utilities
# Reads structure from src/_docs.nix and generates reference docs
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

  # Load documentation manifest from source
  docsManifest = import ../../src/_docs.nix;

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

  # Helper to normalize file entries (string or attrset)
  normalizeFileEntry = entry: if builtins.isString entry then { name = entry; } else entry;

  # Escape backticks for shell echo
  escapeForShell = s: builtins.replaceStrings [ "`" ] [ "\\`" ] s;

  # Generate markdown heading with given level (1-6)
  mkHeading = level: text: lib.concatStrings (lib.genList (_: "#") level) + " ${text}";

  # Generate the shell commands for files.md from manifest
  generateFilesCommands =
    let
      filesConfig = docsManifest.files;
      sections = filesConfig.sections;

      # Heading levels derived from titleLevel
      # title: H1, sections: H2, files: H3, content shifted by 3
      titleLevel = filesConfig.titleLevel or 1;
      sectionLevel = titleLevel + 1;
      fileLevel = titleLevel + 2;
      # Content headings in doc comments start at H1, need to become fileLevel + 1
      contentShift = fileLevel;

      # Generate commands for a single file entry
      fileCommands =
        entry:
        let
          normalized = normalizeFileEntry entry;
          filename = normalized.name;
          fallback = normalized.fallback or null;
          escapedFallback = if fallback != null then escapeForShell fallback else null;
          heading = mkHeading fileLevel filename;
        in
        ''
          echo "${heading}"
          echo ""
        ''
        + (
          if escapedFallback != null then
            ''
              echo "${escapedFallback}"
              echo ""
            ''
          else
            ''
              $NIXDOC file-doc --file "$SRC_DIR/${filename}" --shift-headings ${toString contentShift} || true
              echo ""
            ''
        );

      # Generate commands for a section
      sectionCommands =
        section:
        let
          heading = mkHeading sectionLevel section.name;
        in
        ''
          echo "${heading}"
          echo ""
        ''
        + lib.concatMapStrings fileCommands section.files;

      titleHeading = mkHeading titleLevel filesConfig.title;
    in
    ''
      echo "${titleHeading}"
      echo ""
      echo "<!-- Auto-generated from src/*.nix file-level comments - do not edit -->"
      echo ""
    ''
    + lib.concatMapStrings sectionCommands sections;

  # Generate the shell commands for methods.md from manifest
  generateMethodsCommands =
    let
      methodsConfig = docsManifest.methods;
      sections = methodsConfig.sections;

      # Heading levels derived from titleLevel
      titleLevel = methodsConfig.titleLevel or 1;
      sectionLevel = titleLevel + 1;

      # Generate commands for a single method section
      sectionCommands =
        section:
        let
          hasHeading = section ? heading;
          hasExports = section ? exports;
          exportArg = if hasExports then "--export ${lib.concatStringsSep "," section.exports}" else "";
          heading = mkHeading sectionLevel section.heading;
        in
        (
          if hasHeading then
            ''
              echo ""
              echo "${heading}"
              echo ""
            ''
          else
            ""
        )
        + ''
          $NIXDOC \
            --file "$SRC_DIR/${section.file}" \
            --category "" \
            --description "" \
            --prefix "imp" \
            --anchor-prefix "" \
            ${exportArg}
        '';

      titleHeading = mkHeading titleLevel methodsConfig.title;
    in
    ''
      echo "${titleHeading}"
      echo ""
      echo "<!-- Auto-generated from src/*.nix - do not edit -->"
      echo ""
    ''
    + lib.concatMapStrings sectionCommands sections;

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
      ${generateMethodsCommands}
    } > "$OUT_DIR/methods.md"

    # Generate options.md
    $NIXDOC options \
      --file "$OPTIONS_JSON" \
      --title "Module Options" \
      --anchor-prefix "opt-" \
      > "$OUT_DIR/options.md"

    # Generate files.md from file-level doc comments
    {
      ${generateFilesCommands}
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
