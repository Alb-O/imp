{
  description = "A Nix library for organizing flakes with directory-based imports, named module registries, and automatic input collection.
";

  inputs = {
    # Core dependencies (minimal for library consumers)
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    # Formatter library (standalone, no circular deps)
    imp-fmt.url = "github:imp-nix/imp.fmt";
    imp-fmt.inputs.nixpkgs.follows = "nixpkgs";

    # Dev dependencies (for testing/formatting in this repo)
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    imp-fmt.inputs.treefmt-nix.follows = "treefmt-nix";

    nix-unit.url = "github:nix-community/nix-unit";
    nix-unit.inputs.nixpkgs.follows = "nixpkgs";
    nix-unit.inputs.treefmt-nix.follows = "treefmt-nix";
    nix-unit.inputs.flake-parts.follows = "flake-parts";

    # Optional: docgen for building imp.lib's own docs
    # Consumers who want docs should add their own docgen input
    docgen.url = "github:imp-nix/imp.docgen";
    docgen.inputs.nixpkgs.follows = "nixpkgs";
    docgen.inputs.treefmt-nix.follows = "treefmt-nix";
    docgen.inputs.nix-unit.follows = "nix-unit";
    docgen.inputs.imp-fmt.follows = "imp-fmt";

  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      nix-unit,
      treefmt-nix,
      imp-fmt,
      docgen,
      ...
    }:
    let
      imp = import ./src;
      lib = nixpkgs.lib;
      flakeModule = import ./src/flakeModule.nix;

      # Re-export formatterLib from imp-fmt for backward compatibility
      formatterLib = imp-fmt.lib;
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
      flakeModules = {
        default = flakeModule;
        docs = ./src/flakeModules/docs.nix;
        visualize = ./src/flakeModules/visualize.nix;
      };

      # Reusable formatter configuration (re-exported from imp-fmt)
      # Usage: formatter = imp.formatterLib.make { inherit pkgs treefmt-nix; };
      inherit formatterLib;
    }
    // flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      imports = [
        flakeModule
        ./src/flakeModules/docs.nix
        ./src/flakeModules/visualize.nix
      ];

      # Dogfooding: use imp module to load outputs
      imp = {
        src = ./outputs;
        args = {
          inherit
            self
            nixpkgs
            nix-unit
            treefmt-nix
            imp-fmt
            ;
        };
        registry.src = ./src;

        # Configure docs for imp.lib itself
        docs = {
          manifest = ./docs/manifest.nix;
          srcDir = ./src;
          siteDir = ./docs;
          name = "imp";
          anchorPrefix = "imp";
          optionsModule = ./src/options-schema.nix;
          optionsPrefix = "imp.";
        };
      };
    };
}
