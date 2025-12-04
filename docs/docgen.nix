# Documentation generation for imp
# Configures docgen with imp-specific settings
{
  pkgs,
  lib,
  docgen,
}:
let
  # Use shared options schema for documentation generation
  optionsSchema = import ../src/options-schema.nix { inherit lib; };

  # Use docgen's helper to convert options module to JSON
  optionsJson = docgen.lib.optionsToJson {
    optionsModule = optionsSchema;
    prefix = "imp.";
  };
  optionsJsonFile = pkgs.writeText "imp-options.json" optionsJson;

in
docgen.mkDocgen {
  inherit pkgs lib;
  name = "imp";
  manifest = ./manifest.nix;
  srcDir = ../src;
  siteDir = ./.;
  extraFiles = {
    "README.md" = ../README.md;
  };
  optionsJson = optionsJsonFile;
  anchorPrefix = "imp";
}
