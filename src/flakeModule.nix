/*
  Flake-parts module for imp.

  Automatically loads flake outputs from a directory structure.
  Directory structure maps directly to flake-parts options:

    outputs/
      perSystem/           -> perSystem options (receives pkgs, system, etc.)
        packages.nix       -> perSystem.packages
        apps.nix           -> perSystem.apps
        devShells.nix      -> perSystem.devShells
      nixosConfigurations/ -> flake.nixosConfigurations
      overlays.nix         -> flake.overlays
      systems.nix          -> systems (list of supported systems)

  Files receive standardized arguments matching flake-parts conventions:
    - perSystem files: { pkgs, lib, system, self, self', inputs, inputs', config, ... }
    - flake files: { lib, self, inputs, config, ... }
*/
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
    types
    filterAttrs
    ;

  inherit (flake-parts-lib) mkPerSystemOption;

  impLib = import ./.;
  registryLib = import ./registry.nix { inherit lib; };

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

  # Bound imp instance with lib for passing to modules
  imp = impLib.withLib lib;

  # Build tree from a directory, calling each file with args.
  # Handles both functions and attrsets with __functor.
  buildTree =
    dir: args:
    if builtins.pathExists dir then
      impLib.treeWith lib (f: if builtins.isFunction f || f ? __functor then f args else f) dir
    else
      { };

  # Reserved directory/file names that have special handling
  isSpecialEntry = name: name == cfg.perSystemDir || name == "systems";

  # Use nixpkgs lib when available (has nixosSystem, etc.), fallback to flake-parts lib
  # This ensures lib.nixosSystem works in output files
  nixpkgsLib = inputs.nixpkgs.lib or lib;

  # Standard flake-level args (mirrors flake-parts module args)
  flakeArgs = {
    lib = nixpkgsLib;
    inherit
      self
      inputs
      config
      imp
      ;
    # Allow access to top-level options for introspection
    inherit (config) systems;
    ${cfg.registry.name} = registry;
  }
  // cfg.args;

  # Get flake-level outputs (everything except special entries)
  flakeTree =
    if cfg.src == null then
      { }
    else
      let
        fullTree = buildTree cfg.src flakeArgs;
      in
      filterAttrs (name: _: !isSpecialEntry name) fullTree;

  # Check for systems.nix in src directory
  systemsFile = cfg.src + "/systems.nix";
  hasSystemsFile = cfg.src != null && builtins.pathExists systemsFile;
  systemsFromFile =
    if hasSystemsFile then
      let
        imported = import systemsFile;
      in
      if builtins.isFunction imported then imported flakeArgs else imported
    else
      null;

  # Flake file generation
  flakeFileCfg = cfg.flakeFile;

  # Collect inputs from both outputs dir and registry dir
  inputSources = builtins.filter (p: p != null) [
    cfg.src
    cfg.registry.src
  ];
  collectedInputs =
    if flakeFileCfg.enable && inputSources != [ ] then impLib.collectInputs inputSources else { };

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
  # Use shared options schema for imp.* options
  imports = [ ./options-schema.nix ];

  # Add perSystem-specific options
  options.perSystem = mkPerSystemOption (
    { lib, ... }:
    {
      options.imp = {
        args = mkOption {
          type = types.attrsOf types.unspecified;
          default = { };
          description = "Extra per-system arguments passed to imported files.";
        };

        visualize = {
          wasmDistPath = mkOption {
            type = types.nullOr types.package;
            default = null;
            description = ''
              Path to the imp.graph WASM distribution package.

              Required for the interactive HTML visualization (imp-vis app).
              Set to inputs.imp-graph.packages.''${system}.default to enable.
            '';
          };

          lib = mkOption {
            type = types.nullOr types.attrs;
            default = null;
            description = ''
              The imp.graph visualization library.

              Required for the imp-vis app. Set to inputs.imp-graph.lib to enable.
            '';
          };
        };
      };
    }
  );

  config = lib.mkMerge [
    # Override flakeFile.path default with actual self path
    {
      imp.flakeFile.path = lib.mkDefault (self + "/flake.nix");
    }
    # Systems from file (if present)
    (lib.mkIf (systemsFromFile != null) {
      systems = lib.mkDefault systemsFromFile;
    })

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
              imp
              ;
            ${cfg.registry.name} = registry;
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
          /*
            Regenerate flake.nix from __inputs declarations.

            Files can declare inputs inline:

              # With __functor (when file needs args like pkgs, inputs):
              {
                __inputs.treefmt-nix.url = "github:numtide/treefmt-nix";
                __functor = _: { pkgs, inputs, ... }:
                  inputs.treefmt-nix.lib.evalModule pkgs { ... };
              }

              # Without __functor (static data that declares inputs):
              {
                __inputs.foo.url = "github:owner/foo";
                someKey = "value";
              }

            Run: nix run .#imp-flake
          */
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

    # Registry visualization outputs
    (lib.mkIf (cfg.registry.src != null) {
      # Expose registry as flake output for tooling (imp-refactor, etc.)
      flake.registry = registry;

      perSystem =
        { pkgs, config, ... }:
        let
          analyzeLib = import ./analyze.nix { inherit lib; };
          graph = analyzeLib.analyzeRegistry {
            inherit registry;
            outputsSrc = cfg.src;
          };

          # Access visualization config lazily to avoid infinite recursion
          vizConfig = config.imp.visualize;
          hasVisualization = vizConfig.wasmDistPath != null && vizConfig.lib != null;
        in
        {
          apps = lib.optionalAttrs hasVisualization {
            /*
              Visualize registry dependencies as a graph.

              Analyzes the registry and outputs a dependency graph showing
              how modules reference each other via registry paths.

              Requires perSystem.imp.visualize.wasmDistPath and perSystem.imp.visualize.lib
              to be set. See documentation for how to configure imp-graph.

              Run: nix run .#imp-vis [--format=html|json]
            */
            imp-vis = {
              type = "app";
              program = toString (
                vizConfig.lib.mkVisualizeScript {
                  inherit pkgs graph;
                  wasmDistPath = vizConfig.wasmDistPath;
                }
              );
              meta.description = "Visualize registry dependencies";
            };
          };
        };
    })
  ];
}
