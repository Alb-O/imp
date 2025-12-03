{
  pkgs,
  lib,
  treefmt-nix,
  nixdoc,
  ...
}:
let
  siteDir = ../../site;
  srcDir = ../../src;
  readmeFile = ../../README.md;

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

  # Standalone utilities section (defined in default.nix, not api.nix)
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

  # Generate API reference from source using nixdoc
  apiReference =
    pkgs.runCommand "imp-api-reference"
      {
        nativeBuildInputs = [
          nixdocBin
          mdformat
        ];
        passAsFile = [ "standaloneSection" ];
        inherit standaloneSection;
      }
      ''
        mkdir -p $out
        {
          echo "# API Methods"
          echo ""
          echo "<!-- Auto-generated from src/api.nix - do not edit -->"
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

          cat $standaloneSectionPath
        } > $out/methods.md

        # Format the generated markdown
        mdformat $out/methods.md
      '';

  # Build site with generated reference
  siteWithGeneratedDocs = pkgs.runCommand "imp-site-src" { } ''
    cp -r ${siteDir} $out
    chmod -R +w $out
    cp ${apiReference}/methods.md $out/src/reference/methods.md
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
