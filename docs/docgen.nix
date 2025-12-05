# Documentation generation for imp
# Configures docgen with imp-specific settings
{
  pkgs,
  lib,
  docgen,
}:
let
  # Use docgen's helper to convert options module to JSON
  optionsJson = docgen.lib.optionsToJson {
    optionsModule = ../src/options-schema.nix;
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
  extraFiles = { };
  optionsJson = optionsJsonFile;
  anchorPrefix = "imp";
}
