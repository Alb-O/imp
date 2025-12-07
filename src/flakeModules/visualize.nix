/**
  Visualization module for imp consumers.

  Activates automatically when the consumer's flake includes an `imp-graph` input.
  Uses imp.graph's Rust/WASM force-directed graph to render interactive HTML
  visualizations of registry dependencies.

  # Example

  ```nix
  {
    inputs.imp-graph.url = "github:imp-nix/imp.graph";
    inputs.imp-graph.inputs.nixpkgs.follows = "nixpkgs";

    outputs = inputs@{ flake-parts, imp, ... }:
      flake-parts.lib.mkFlake { inherit inputs; } {
        imports = [
          imp.flakeModules.default
          imp.flakeModules.visualize
        ];
      };
  }
  ```

  This adds `apps.graph`, which scans the registry for `registry.X.Y`
  references and generates a dependency graph. Run `nix run .#graph` to
  open an interactive HTML visualization in your browser.

  The module also configures `perSystem.imp.visualize.wasmDistPath` and
  `perSystem.imp.visualize.lib`, enabling the `imp-graph` app from the main
  flakeModule if you have a registry configured.
*/
{
  lib,
  config,
  inputs,
  ...
}:
let
  inherit (lib) mkOption types mkIf;

  hasImpGraph = inputs ? imp-graph;
in
{
  options.imp.visualize = {
    enable = mkOption {
      type = types.bool;
      default = hasImpGraph;
      description = ''
        Enable visualization features.
        Automatically enabled when the imp-graph input is present.
      '';
    };
  };

  config = mkIf (config.imp.visualize.enable && hasImpGraph) {
    perSystem =
      { pkgs, system, ... }:
      let
        wasmDistPath = inputs.imp-graph.packages.${system}.default;
        vizLib = inputs.imp-graph.lib;
      in
      {
        # Configure the perSystem.imp.visualize options for imp-graph app
        imp.visualize = {
          wasmDistPath = wasmDistPath;
          lib = vizLib;
        };

        # Standalone graph app for analyzing any path
        apps.graph = {
          type = "app";
          meta.description = "Visualize imp registry dependencies (standalone)";
          program = toString (
            vizLib.mkVisualizeScript {
              inherit pkgs wasmDistPath;
              impSrc = inputs.imp;
              nixpkgsFlake = inputs.nixpkgs;
              name = "imp-graph";
            }
          );
        };
      };
  };
}
