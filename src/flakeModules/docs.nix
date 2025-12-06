/**
  Documentation generation module for imp consumers.

  Activates automatically when the consumer's flake includes a `docgen` input.
  Uses imp.docgen to generate API reference from Nix source files and build
  mdBook documentation sites.

  # Example

  ```nix
  {
    inputs.docgen.url = "github:imp-nix/imp.docgen";
    inputs.docgen.inputs.nixpkgs.follows = "nixpkgs";

    outputs = inputs@{ flake-parts, imp, ... }:
      flake-parts.lib.mkFlake { inherit inputs; } {
        imports = [
          imp.flakeModules.default
          imp.flakeModules.docs
        ];
        imp.docs = {
          manifest = ./docs/manifest.nix;
          srcDir = ./src;
          siteDir = ./docs;
        };
      };
  }
  ```

  This adds three outputs: `apps.docs` serves the documentation locally with
  live reload, `apps.build-docs` builds to a local directory, and `packages.docs`
  produces a derivation containing the built site.
*/
{
  lib,
  config,
  inputs,
  ...
}:
let
  inherit (lib) mkOption types mkIf;

  hasDocgen = inputs ? docgen;
in
{
  options.imp.docs = {
    enable = mkOption {
      type = types.bool;
      default = hasDocgen;
      description = ''
        Enable documentation generation.
        Automatically enabled when the docgen input is present.
      '';
    };

    manifest = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to the docgen manifest file that describes documentation structure.
      '';
    };

    srcDir = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to the source directory to generate API reference from.
      '';
    };

    siteDir = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to the documentation site directory (contains book.toml, etc).
      '';
    };

    name = mkOption {
      type = types.str;
      default = "docs";
      description = ''
        Name for the documentation package.
      '';
    };

    anchorPrefix = mkOption {
      type = types.str;
      default = "";
      description = ''
        Prefix for anchor IDs in generated documentation.
      '';
    };

    optionsModule = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Optional path to a NixOS-style options module to document.
      '';
    };

    optionsPrefix = mkOption {
      type = types.str;
      default = "";
      description = ''
        Prefix for options (e.g., "imp." for imp.* options).
      '';
    };
  };

  config = mkIf (config.imp.docs.enable && hasDocgen) (
    let
      cfg = config.imp.docs;
    in
    {
      perSystem =
        { pkgs, ... }:
        let
          optionsJson =
            if cfg.optionsModule != null then
              let
                json = inputs.docgen.lib.optionsToJson {
                  optionsModule = cfg.optionsModule;
                  prefix = cfg.optionsPrefix;
                };
              in
              pkgs.writeText "${cfg.name}-options.json" json
            else
              null;

          dg = inputs.docgen.mkDocgen {
            inherit pkgs;
            inherit (cfg) name anchorPrefix;
            manifest =
              if cfg.manifest == null then
                throw "imp.docs.manifest must be set when docs are enabled"
              else
                cfg.manifest;
            srcDir =
              if cfg.srcDir == null then
                throw "imp.docs.srcDir must be set when docs are enabled"
              else
                cfg.srcDir;
            siteDir = cfg.siteDir;
            inherit optionsJson;
          };
        in
        {
          apps.docs = {
            type = "app";
            meta.description = "Serve documentation locally with live reload";
            program = toString dg.serveDocsScript;
          };

          apps.build-docs = {
            type = "app";
            meta.description = "Build documentation to local directory";
            program = toString dg.buildDocsScript;
          };

          packages.docs = dg.docs;
        };
    }
  );
}
