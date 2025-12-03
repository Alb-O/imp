{
  pkgs,
  lib,
  nixdoc,
  ...
}:
let
  siteDir = ../../site;
  srcDir = ../../src;
  readmeFile = ../../README.md;

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

  # Evaluate the module using lib.evalModules to get proper options with loc metadata
  evaluatedModule = lib.evalModules {
    modules = [ optionsSchema ];
  };

  # Extract options using lib.optionAttrSetToDocList (the standard nixpkgs approach)
  rawOpts = lib.optionAttrSetToDocList evaluatedModule.options;
  # Filter to visible, non-internal, and only imp.* options (exclude _module.*)
  filteredOpts = lib.filter (
    opt: (opt.visible or true) && !(opt.internal or false) && lib.hasPrefix "imp." opt.name
  ) rawOpts;
  # Convert to the JSON format expected by nixdoc options command
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
  # Serialize to JSON
  optionsJson = builtins.toJSON optionsNix;

  # Generate API reference from source using nixdoc
  apiReference =
    pkgs.runCommand "imp-api-reference"
      {
        nativeBuildInputs = [
          nixdocBin
          mdformat
        ];
        passAsFile = [
          "optionsJson"
        ];
        inherit optionsJson;
      }
      ''
        mkdir -p $out
        {
          echo "# API Methods"
          echo ""
          echo "<!-- Auto-generated from src/*.nix - do not edit -->"
          echo ""
          nixdoc \
            --file ${srcDir}/api.nix \
            --category "" \
            --description "" \
            --prefix "imp" \
            --anchor-prefix ""

          echo ""
          echo "## Registry"
          echo ""
          nixdoc \
            --file ${srcDir}/registry.nix \
            --category "" \
            --description "" \
            --prefix "imp" \
            --anchor-prefix ""

          echo ""
          echo "## Format Flake"
          echo ""
          nixdoc \
            --file ${srcDir}/format-flake.nix \
            --category "" \
            --description "" \
            --prefix "imp" \
            --anchor-prefix ""

          echo ""
          echo "## Analyze"
          echo ""
          nixdoc \
            --file ${srcDir}/analyze.nix \
            --category "" \
            --description "" \
            --prefix "imp" \
            --anchor-prefix ""

          echo ""
          echo "## Visualize"
          echo ""
          nixdoc \
            --file ${srcDir}/visualize.nix \
            --category "" \
            --description "" \
            --prefix "imp" \
            --anchor-prefix ""

          echo ""
          echo "## Standalone Utilities"
          echo ""
          nixdoc \
            --file ${srcDir}/default.nix \
            --category "" \
            --description "" \
            --prefix "imp" \
            --anchor-prefix "" \
            --export collectInputs,collectAndFormatFlake
        } > $out/methods.md

        # Generate options reference using nixdoc options command
        nixdoc options \
          --file $optionsJsonPath \
          --title "Module Options" \
          --anchor-prefix "opt-" \
          > $out/options.md

        # Format the generated markdown
        mdformat $out/methods.md
        mdformat $out/options.md
      '';

  # Build site with generated reference
  siteWithGeneratedDocs = pkgs.runCommand "imp-site-src" { } ''
    cp -r ${siteDir} $out
    chmod -R +w $out
    cp ${apiReference}/methods.md $out/src/reference/methods.md
    cp ${apiReference}/options.md $out/src/reference/options.md
    cp ${readmeFile} $out/src/README.md
  '';
in
{
  docs = pkgs.stdenvNoCC.mkDerivation {
    name = "imp-docs";
    src = siteWithGeneratedDocs;
    nativeBuildInputs = [ pkgs.mdbook ];
    buildPhase = ''
      runHook preBuild
      mdbook build --dest-dir $out
      runHook postBuild
    '';
    dontInstall = true;
  };

  # Expose for debugging
  api-reference = apiReference;
}
