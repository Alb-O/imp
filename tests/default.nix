# Unit tests for imp
{ lib }:
let
  imp = import ./../src;
  it = imp;
  lit = it.withLib lib;
in
{
  leafs."test fails if no lib has been set" = {
    expr = it.leafs ./fixtures;
    expectedError.type = "ThrownError";
  };

  leafs."test succeeds when lib has been set" = {
    expr = (it.withLib lib).leafs ./fixtures/hello;
    expected = [ ];
  };

  leafs."test only returns nix non-ignored files" = {
    expr = lit.leafs ./fixtures/a;
    expected = [
      ./fixtures/a/a_b.nix
      ./fixtures/a/b/b_a.nix
      ./fixtures/a/b/m.nix
    ];
  };

  filter."test returns empty if no nix files with true predicate" = {
    expr = (lit.filter (_: false)).leafs ./fixtures;
    expected = [ ];
  };

  filter."test only returns nix files with true predicate" = {
    expr = (lit.filter (lib.hasSuffix "m.nix")).leafs ./fixtures;
    expected = [ ./fixtures/a/b/m.nix ];
  };

  filter."test multiple `filter`s compose" = {
    expr = ((lit.filter (lib.hasInfix "b/")).filter (lib.hasInfix "_")).leafs ./fixtures;
    expected = [ ./fixtures/a/b/b_a.nix ];
  };

  match."test returns empty if no files match regex" = {
    expr = (lit.match "badregex").leafs ./fixtures;
    expected = [ ];
  };

  match."test returns files matching regex" = {
    expr = (lit.match ".*/[^/]+_[^/]+\.nix").leafs ./fixtures;
    expected = [
      ./fixtures/a/a_b.nix
      ./fixtures/a/b/b_a.nix
    ];
  };

  matchNot."test returns files not matching regex" = {
    expr = (lit.matchNot ".*/[^/]+_[^/]+\.nix").leafs ./fixtures/a/b;
    expected = [
      ./fixtures/a/b/m.nix
    ];
  };

  match."test `match` composes with `filter`" = {
    expr = ((lit.match ".*a_b.nix").filter (lib.hasInfix "/a/")).leafs ./fixtures;
    expected = [ ./fixtures/a/a_b.nix ];
  };

  match."test multiple `match`s compose" = {
    expr = ((lit.match ".*/[^/]+_[^/]+\.nix").match ".*b\.nix").leafs ./fixtures;
    expected = [ ./fixtures/a/a_b.nix ];
  };

  map."test transforms each matching file with function" = {
    expr = (lit.map import).leafs ./fixtures/x;
    expected = [ "z" ];
  };

  map."test `map` composes with `filter`" = {
    expr = ((lit.filter (lib.hasInfix "/x")).map import).leafs ./fixtures;
    expected = [ "z" ];
  };

  map."test multiple `map`s compose" = {
    expr = ((lit.map import).map builtins.stringLength).leafs ./fixtures/x;
    expected = [ 1 ];
  };

  addPath."test `addPath` prepends a path to filter" = {
    expr = (lit.addPath ./fixtures/x).files;
    expected = [ ./fixtures/x/y.nix ];
  };

  addPath."test `addPath` can be called multiple times" = {
    expr = ((lit.addPath ./fixtures/x).addPath ./fixtures/a/b).files;
    expected = [
      ./fixtures/x/y.nix
      ./fixtures/a/b/b_a.nix
      ./fixtures/a/b/m.nix
    ];
  };

  addPath."test `addPath` identity" = {
    expr = ((lit.addPath ./fixtures/x).addPath ./fixtures/a/b).files;
    expected = lit.leafs [
      ./fixtures/x
      ./fixtures/a/b
    ];
  };

  new."test `new` returns a clear state" = {
    expr = lib.pipe lit [
      (i: i.addPath ./fixtures/x)
      (i: i.addPath ./fixtures/a/b)
      (i: i.new)
      (i: i.addPath ./fixtures/modules/hello-world)
      (i: i.withLib lib)
      (i: i.files)
    ];
    expected = [ ./fixtures/modules/hello-world/mod.nix ];
  };

  initFilter."test can change the initial filter to look for other file types" = {
    expr = (lit.initFilter (p: lib.hasSuffix ".txt" p)).leafs [ ./fixtures/a ];
    expected = [ ./fixtures/a/a.txt ];
  };

  initFilter."test initf does filter non-paths" = {
    expr =
      let
        mod = (it.initFilter (x: !(x ? config.boom))) [
          {
            options.hello = lib.mkOption {
              default = "world";
              type = lib.types.str;
            };
          }
          {
            config.boom = "boom";
          }
        ];
        res = lib.modules.evalModules { modules = [ mod ]; };
      in
      res.config.hello;
    expected = "world";
  };

  addAPI."test extends the API available on an imp object" = {
    expr =
      let
        extended = lit.addAPI { helloOption = self: self.addPath ./fixtures/modules/hello-option; };
      in
      extended.helloOption.files;
    expected = [ ./fixtures/modules/hello-option/mod.nix ];
  };

  addAPI."test preserves previous API extensions on an imp object" = {
    expr =
      let
        first = lit.addAPI { helloOption = self: self.addPath ./fixtures/modules/hello-option; };
        second = first.addAPI { helloWorld = self: self.addPath ./fixtures/modules/hello-world; };
        extended = second.addAPI { res = self: self.helloOption.files; };
      in
      extended.res;
    expected = [ ./fixtures/modules/hello-option/mod.nix ];
  };

  addAPI."test API extensions are late bound" = {
    expr =
      let
        first = lit.addAPI { res = self: self.late; };
        extended = first.addAPI { late = _self: "hello"; };
      in
      extended.res;
    expected = "hello";
  };

  pipeTo."test pipes list into a function" = {
    expr = (lit.map lib.pathType).pipeTo (lib.length) ./fixtures/x;
    expected = 1;
  };

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

  leafs."test loads from hidden directory but excludes sub-hidden" = {
    expr = lit.leafs ./fixtures/a/b/_c;
    expected = [ ./fixtures/a/b/_c/d/e.nix ];
  };

  # Tree tests
  tree."test fails if no lib has been set" = {
    expr = it.tree ./fixtures/tree-test;
    expectedError.type = "EvalError";
  };

  tree."test builds nested attrset from directory" = {
    expr = lit.tree ./fixtures/tree-test;
    expected = {
      default = {
        isDefault = true;
      };
      top = {
        level = "top";
      };
      packages = {
        foo = {
          name = "foo";
        };
        bar = {
          name = "bar";
        };
      };
      modules = {
        simple = {
          value = "simple";
        };
        nested = {
          deep = {
            value = "deep";
          };
        };
      };
    };
  };

  tree."test can access nested attributes" = {
    expr = (lit.tree ./fixtures/tree-test).packages.foo.name;
    expected = "foo";
  };

  tree."test suffix_ escapes to attribute name" = {
    expr = (lit.tree ./fixtures/tree-test).default;
    expected = {
      isDefault = true;
    };
  };

  tree."test deeply nested access" = {
    expr = (lit.tree ./fixtures/tree-test).modules.nested.deep.value;
    expected = "deep";
  };

  tree."test filter applies to tree" = {
    expr = (lit.filter (lib.hasInfix "packages")).tree ./fixtures/tree-test;
    expected = {
      packages = {
        foo = {
          name = "foo";
        };
        bar = {
          name = "bar";
        };
      };
    };
  };

  mapTree."test transforms imported values" = {
    expr = (lit.mapTree (x: x // { extra = true; })).tree ./fixtures/tree-test/packages;
    expected = {
      foo = {
        name = "foo";
        extra = true;
      };
      bar = {
        name = "bar";
        extra = true;
      };
    };
  };

  mapTree."test multiple mapTrees compose" = {
    expr =
      ((lit.mapTree (x: x // { first = true; })).mapTree (x: x // { second = true; })).tree
        ./fixtures/tree-test/packages;
    expected = {
      foo = {
        name = "foo";
        first = true;
        second = true;
      };
      bar = {
        name = "bar";
        first = true;
        second = true;
      };
    };
  };
}
