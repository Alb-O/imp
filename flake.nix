{
  description = "A Nix library for organizing flakes with directory-based imports, named module registries, and automatic input collection.
";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nix-unit.url = "github:nix-community/nix-unit";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    docgen.url = "github:imp-nix/imp.docgen";
    imp-graph.url = "github:imp-nix/imp.graph";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      nix-unit,
      treefmt-nix,
      docgen,
      imp-graph,
      ...
    }:
    let
      imp = import ./src;
      lib = nixpkgs.lib;
      flakeModule = import ./src/flakeModule.nix;
    in
    {
      tests = import ./tests { inherit lib; };

      # Export imp as a callable functor with essential methods
      __functor = imp.__functor;
      __config = imp.__config;
      withLib = imp.withLib;
      addPath = imp.addPath;
      addAPI = imp.addAPI;
      new = imp.new;

      # High-level tree operations (require withLib first)
      tree = imp.tree;
      treeWith = imp.treeWith;
      configTree = imp.configTree;
      configTreeWith = imp.configTreeWith;

      # Flake generation utilities (standalone, no nixpkgs needed)
      collectInputs = imp.collectInputs;
      formatInputs = imp.formatInputs;
      formatFlake = imp.formatFlake;
      collectAndFormatFlake = imp.collectAndFormatFlake;

      # Flake-parts integration
      flakeModules.default = flakeModule;
    }
    // flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      imports = [ flakeModule ];

      # Dogfooding: use imp module to load outputs
      imp = {
        src = ./outputs;
        args = {
          inherit
            self
            nixpkgs
            nix-unit
            treefmt-nix
            docgen
            imp-graph
            ;
        };
        registry.src = ./src;
      };

      # Configure visualization for imp-vis app
      perSystem =
        { system, ... }:
        {
          imp.visualize = {
            wasmDistPath = imp-graph.packages.${system}.default;
            lib = imp-graph.lib;
          };
        };
    };
}
