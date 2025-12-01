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
      import-tree = import ./nix;
    in
    {
      __functor = _: import-tree.__functor import-tree;
      inherit (import-tree)
        __config
        filter
        filterNot
        match
        matchNot
        map
        addPath
        addAPI
        withLib
        initFilter
        pipeTo
        leafs
        new
        result
        ;
      tests = import ./tests { lib = nixpkgs.lib; };
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        treefmtEval = treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
          settings.global.excludes = [ "tests/fixtures/*" ];
        };
      in
      {
        formatter = treefmtEval.config.build.wrapper;

        checks = {
          formatting = treefmtEval.config.build.check self;
          nix-unit =
            pkgs.runCommand "nix-unit-tests"
              {
                nativeBuildInputs = [ nix-unit.packages.${system}.default ];
              }
              ''
                export HOME=$TMPDIR
                nix-unit --expr 'import ${self}/tests { lib = import ${nixpkgs}/lib; }'
                touch $out
              '';
        };

        apps.tests = {
          type = "app";
          program = toString (
            pkgs.writeShellScript "run-tests" ''
              ${nix-unit.packages.${system}.default}/bin/nix-unit --flake .#tests
            ''
          );
        };

        devShells.default = pkgs.mkShell {
          packages = [ nix-unit.packages.${system}.default ];
          inputsFrom = [ treefmtEval.config.build.devShell ];
        };
      }
    );
}
