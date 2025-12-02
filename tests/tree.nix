# Tests for tree, mapTree, configTree, configTreeWith
{
  lib,
  imp,
}:
let
  it = imp;
  lit = it.withLib lib;
in
{
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

  # mapTree tests
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

  # configTree tests - builds modules where path = option path
  configTree."test fails if no lib has been set" = {
    expr = it.configTree ./fixtures/config-tree;
    expectedError.type = "EvalError";
  };

  configTree."test builds nested config from directory structure" = {
    expr =
      let
        module = lit.configTree ./fixtures/config-tree;
        mockArgs = {
          config = { };
          lib = lib;
          pkgs = { };
        };
        result = module mockArgs;
      in
      result.config;
    expected = {
      programs = {
        git = {
          enable = true;
          userName = "Test User";
        };
        zsh = {
          enable = true;
          autosuggestion.enable = true;
        };
      };
      services = {
        nginx = {
          enable = true;
          recommendedGzipSettings = true;
        };
      };
      top-level = {
        value = "top";
        computed = "ab";
      };
    };
  };

  configTree."test can access deeply nested config values" = {
    expr =
      let
        module = lit.configTree ./fixtures/config-tree;
        mockArgs = {
          config = { };
          lib = lib;
          pkgs = { };
        };
        result = module mockArgs;
      in
      result.config.programs.git.userName;
    expected = "Test User";
  };

  configTree."test directory with default.nix is treated as single value" = {
    expr =
      let
        module = lit.configTree ./fixtures/config-tree;
        mockArgs = {
          config = { };
          lib = lib;
          pkgs = { };
        };
        result = module mockArgs;
      in
      result.config.services.nginx;
    expected = {
      enable = true;
      recommendedGzipSettings = true;
    };
  };

  configTree."test filter applies to configTree" = {
    expr =
      let
        module = (lit.filter (lib.hasInfix "programs")).configTree ./fixtures/config-tree;
        mockArgs = {
          config = { };
          lib = lib;
          pkgs = { };
        };
        result = module mockArgs;
      in
      result.config;
    expected = {
      programs = {
        git = {
          enable = true;
          userName = "Test User";
        };
        zsh = {
          enable = true;
          autosuggestion.enable = true;
        };
      };
    };
  };

  # configTreeWith tests
  configTreeWith."test passes extra args to config files" = {
    expr =
      let
        module = lit.configTreeWith { customArg = "hello"; } ./fixtures/config-tree-extra;
        mockArgs = {
          config = { };
          lib = lib;
          pkgs = { };
        };
        result = module mockArgs;
      in
      result.config;
    expected = {
      test = {
        fromCustomArg = "hello";
      };
    };
  };
}
