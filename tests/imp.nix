# Tests for imp as a module system integration
{
  lib,
  imp,
}:
let
  it = imp;
  lit = it.withLib lib;
in
{
  imp."test does not break if given a path to a file instead of a directory." = {
    expr = lit.leafs ./fixtures/x/y.nix;
    expected = [ ./fixtures/x/y.nix ];
  };

  imp."test returns a module with a single imported nested module having leafs" = {
    expr =
      let
        oneElement = arr: if lib.length arr == 1 then lib.elemAt arr 0 else throw "Expected one element";
        module = it ./fixtures/x;
        inner = (oneElement module.imports) { inherit lib; };
      in
      oneElement inner.imports;
    expected = ./fixtures/x/y.nix;
  };

  imp."test evaluates returned module as part of module-eval" = {
    expr =
      let
        res = lib.modules.evalModules { modules = [ (it ./fixtures/modules) ]; };
      in
      res.config.hello;
    expected = "world";
  };

  imp."test can itself be used as a module" = {
    expr =
      let
        res = lib.modules.evalModules { modules = [ (it.addPath ./fixtures/modules) ]; };
      in
      res.config.hello;
    expected = "world";
  };

  imp."test take as arg anything path convertible" = {
    expr = lit.leafs [
      {
        outPath = ./fixtures/modules/hello-world;
      }
    ];
    expected = [ ./fixtures/modules/hello-world/mod.nix ];
  };

  imp."test passes non-paths without string conversion" = {
    expr =
      let
        mod = it [
          {
            options.hello = lib.mkOption {
              default = "world";
              type = lib.types.str;
            };
          }
        ];
        res = lib.modules.evalModules { modules = [ mod ]; };
      in
      res.config.hello;
    expected = "world";
  };

  imp."test can take other imps as if they were paths" = {
    expr = (lit.filter (lib.hasInfix "mod")).leafs [
      (it.addPath ./fixtures/modules/hello-option)
      ./fixtures/modules/hello-world
    ];
    expected = [
      ./fixtures/modules/hello-option/mod.nix
      ./fixtures/modules/hello-world/mod.nix
    ];
  };
}
