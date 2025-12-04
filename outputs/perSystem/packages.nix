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

  # Import shared docgen utilities
  docgen = import ./_docgen.nix { inherit pkgs lib nixdoc; };

  # Generate API reference from source using nixdoc
  apiReference =
    pkgs.runCommand "imp-api-reference"
      {
        nativeBuildInputs = [
          docgen.nixdocBin
          docgen.mdformat
        ];
      }
      ''
        mkdir -p $out
        ${docgen.generateDocsScript} ${srcDir} $out ${docgen.optionsJsonFile}
      '';

  # Build site with generated reference
  siteWithGeneratedDocs = pkgs.runCommand "imp-site-src" { } ''
    cp -r ${siteDir} $out
    chmod -R +w $out
    cp ${apiReference}/methods.md $out/src/reference/methods.md
    cp ${apiReference}/options.md $out/src/reference/options.md
    cp ${apiReference}/files.md $out/src/reference/files.md
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
