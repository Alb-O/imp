{
  description = "Recursively import Nix modules from a directory";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix-unit.url = "github:nix-community/nix-unit";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      nix-unit,
      treefmt-nix,
      ...
    }:
    let
      imp = import ./src;
      lib = nixpkgs.lib;
    in
    {
      tests = import ./tests { inherit lib; };
    }
    // removeAttrs imp [
      "files"
      "result"
    ]
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        args = {
          inherit
            self
            pkgs
            nixpkgs
            nix-unit
            treefmt-nix
            ;
        };
        # Dogfooding: use .treeWith to load per-system outputs from ./outputs
        outputs = imp.treeWith lib (f: f args) ./outputs;
      in
      outputs
    );
}
