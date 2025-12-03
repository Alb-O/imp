# Flake-parts module for imp.
#
# Automatically loads flake outputs from a directory structure.
# See option descriptions below for usage details.
{
  lib,
  flake-parts-lib,
  config,
  inputs,
  self,
  ...
}:
let
  inherit (lib)
    mkOption
    mkEnableOption
    types
    filterAttrs
    ;

  inherit (flake-parts-lib) mkPerSystemOption;

  impLib = import ./.;
  registryLib = import ./registry.nix { inherit lib; };
  migrateLib = import ./migrate.nix { inherit lib; };

  cfg = config.imp;

  # Build the registry from configured sources
  registry =
    if cfg.registry.src == null then
      { }
    else
      let
        autoRegistry = registryLib.buildRegistry cfg.registry.src;
      in
      lib.recursiveUpdate autoRegistry cfg.registry.modules;

  # Build tree from a directory, calling each file with args.
  # Handles both functions and attrsets with __functor.
  buildTree =
    dir: args:
    if builtins.pathExists dir then
      impLib.treeWith lib (f: if builtins.isFunction f || f ? __functor then f args else f) dir
    else
      { };

  isPerSystemDir = name: name == cfg.perSystemDir;

  # Get flake-level outputs (everything except perSystem dir)
  flakeTree =
    if cfg.src == null then
      { }
    else
      let
        fullTree = buildTree cfg.src (
          {
            inherit
              lib
              self
              inputs
              registry
              ;
          }
          // cfg.args
        );
      in
      filterAttrs (name: _: !isPerSystemDir name) fullTree;

  # Flake file generation
  flakeFileCfg = cfg.flakeFile;
  collectedInputs = if flakeFileCfg.enable then impLib.collectInputs cfg.src else { };
  generatedFlakeContent =
    if flakeFileCfg.enable then
      impLib.formatFlake {
        inherit (flakeFileCfg)
          description
          coreInputs
          outputsFile
          header
          ;
        inherit collectedInputs;
      }
    else
      "";

in
{
  options = {
    imp = {
      src = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Directory containing flake outputs to import.

          Example structure:
            outputs/
              perSystem/
                packages.nix     -> perSystem.packages
                devShells.nix    -> perSystem.devShells
              nixosConfigurations/
                server.nix       -> flake.nixosConfigurations.server
              overlays.nix       -> flake.overlays
        '';
      };

      args = mkOption {
        type = types.attrsOf types.unspecified;
        default = { };
        description = ''
          Extra arguments passed to all imported files.

          Files receive: { lib, self, inputs, ... } // args (for flake outputs)
          Or: { pkgs, lib, system, self, self', inputs, inputs', ... } // args (for perSystem)

          User-provided args take precedence, allowing you to override lib
          with a custom extended version.
        '';
      };

      perSystemDir = mkOption {
        type = types.str;
        default = "perSystem";
        description = "Subdirectory name for per-system outputs.";
      };

      registry = {
        src = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = ''
            Root directory to scan for building the module registry.

            The registry maps directory structure to named modules:
              nix/
                home/alice/     -> registry.home.alice
                modules/nixos/  -> registry.modules.nixos

            Files can then reference modules by name instead of path:
              { registry, ... }:
              {
                imports = [ registry.modules.home ];
              }
          '';
        };

        modules = mkOption {
          type = types.attrsOf types.unspecified;
          default = { };
          description = ''
            Explicit module name -> path mappings.
            These override auto-discovered modules from registry.src.

            Example:
              registry.modules = {
                specialModule = ./path/to/special.nix;
              };
          '';
        };

        migratePaths = mkOption {
          type = types.listOf types.path;
          default = [ ];
          description = ''
            Directories to scan for registry references when detecting renames.

            If empty, defaults to [ imp.src ] when registry.src is set.

            Example:
              registry.migratePaths = [ ./nix/outputs ./nix/flake ];
          '';
        };
      };

      flakeFile = {
        enable = mkEnableOption "flake.nix generation from __inputs declarations";

        path = mkOption {
          type = types.path;
          default = self + "/flake.nix";
          description = "Path to flake.nix file to generate/check.";
        };

        description = mkOption {
          type = types.str;
          default = "";
          description = "Flake description field.";
        };

        coreInputs = mkOption {
          type = types.attrsOf types.unspecified;
          default = { };
          description = ''
            Core inputs always included in flake.nix (e.g., nixpkgs, flake-parts).

            Example:
              coreInputs = {
                nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
                flake-parts.url = "github:hercules-ci/flake-parts";
              };
          '';
        };

        outputsFile = mkOption {
          type = types.str;
          default = "./outputs.nix";
          description = "Path to outputs.nix (relative to flake.nix).";
        };

        header = mkOption {
          type = types.str;
          default = "# Auto-generated by imp - DO NOT EDIT\n# Regenerate with: nix run .#imp-flake";
          description = "Header comment for generated flake.nix.";
        };
      };
    };

    perSystem = mkPerSystemOption (
      { ... }:
      {
        options.imp = {
          args = mkOption {
            type = types.attrsOf types.unspecified;
            default = { };
            description = "Extra per-system arguments passed to imported files.";
          };
        };
      }
    );
  };

  config = lib.mkMerge [
    # Main imp config
    (lib.mkIf (cfg.src != null) {
      flake = flakeTree;

      perSystem =
        {
          pkgs,
          system,
          self',
          inputs',
          config,
          ...
        }:
        let
          perSystemPath = cfg.src + "/${cfg.perSystemDir}";
          perSystemArgs = {
            inherit
              lib
              pkgs
              system
              self
              self'
              inputs
              inputs'
              registry
              ;
          }
          // cfg.args
          // config.imp.args;
        in
        buildTree perSystemPath perSystemArgs;
    })

    # Flake file generation outputs
    (lib.mkIf flakeFileCfg.enable {
      perSystem =
        { pkgs, ... }:
        {
          # Regenerate flake.nix from __inputs declarations.
          #
          # Files can declare inputs inline:
          #
          #   # With __functor (when file needs args like pkgs, inputs):
          #   {
          #     __inputs.treefmt-nix.url = "github:numtide/treefmt-nix";
          #     __functor = _: { pkgs, inputs, ... }:
          #       inputs.treefmt-nix.lib.evalModule pkgs { ... };
          #   }
          #
          #   # Without __functor (static data that declares inputs):
          #   {
          #     __inputs.foo.url = "github:owner/foo";
          #     someKey = "value";
          #   }
          #
          # Run: nix run .#imp-flake
          apps.imp-flake = {
            type = "app";
            program = toString (
              pkgs.writeShellScript "imp-flake" ''
                printf '%s' ${lib.escapeShellArg generatedFlakeContent} > flake.nix
                echo "Generated flake.nix"
              ''
            );
            meta.description = "Regenerate flake.nix from __inputs declarations";
          };

          # Checks that flake.nix matches what would be generated.
          # Fails if flake.nix is out of sync with __inputs declarations.
          checks.flake-up-to-date =
            pkgs.runCommand "flake-up-to-date"
              {
                expected = generatedFlakeContent;
                actual = builtins.readFile flakeFileCfg.path;
                passAsFile = [
                  "expected"
                  "actual"
                ];
              }
              ''
                if diff -u "$expectedPath" "$actualPath"; then
                  echo "flake.nix is up-to-date"
                  touch $out
                else
                  echo ""
                  echo "ERROR: flake.nix is out of date!"
                  echo "Run 'nix run .#imp-flake' to regenerate it."
                  exit 1
                fi
              '';
        };
    })

    # Registry migration outputs
    (lib.mkIf (cfg.registry.src != null) {
      perSystem =
        { pkgs, ... }:
        let
          migratePaths =
            if cfg.registry.migratePaths != [ ] then
              cfg.registry.migratePaths
            else if cfg.src != null then
              [ cfg.src ]
            else
              [ ];

          migration = migrateLib.detectRenames {
            inherit registry;
            paths = migratePaths;
          };
        in
        {
          # Detect registry renames and generate fix commands.
          #
          # When directories are renamed, registry paths change. This app:
          # 1. Scans files for registry.X.Y patterns
          # 2. Compares against current registry to find broken references
          # 3. Suggests mappings from old names to new names
          # 4. Generates sed commands to fix all references
          #
          # Run: nix run .#imp-registry
          apps.imp-registry = {
            type = "app";
            program = toString (pkgs.writeShellScript "imp-registry" migration.script);
            meta.description = "Detect and fix registry path renames";
          };
        };
    })
  ];
}
