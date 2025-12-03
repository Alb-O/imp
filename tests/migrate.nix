# Tests for migrate: detecting renames and generating fix commands
{ lib, ... }:
let
  migrateLib = import ../src/migrate.nix { inherit lib; };
  registryLib = import ../src/registry.nix { inherit lib; };

  # Build a registry from the existing registry-test fixture
  # This represents the "current" state after renames
  testRegistry = registryLib.buildRegistry ./fixtures/registry-test;
in
{
  # extractRegistryRefs tests
  migrate."test extracts single registry reference" = {
    expr = migrateLib.extractRegistryRefs "registry" ''
      { registry, ... }:
      { imports = [ registry.home.alice ]; }
    '';
    expected = [ "home.alice" ];
  };

  migrate."test extracts multiple registry references" = {
    expr = migrateLib.extractRegistryRefs "registry" ''
      { registry, ... }:
      {
        imports = [
          registry.home.alice
          registry.modules.nixos
          registry.hosts.server
        ];
      }
    '';
    expected = [
      "home.alice"
      "modules.nixos"
      "hosts.server"
    ];
  };

  migrate."test extracts references from same line" = {
    expr = migrateLib.extractRegistryRefs "registry" ''
      foo = registry.a.b; bar = registry.c.d;
    '';
    expected = [
      "a.b"
      "c.d"
    ];
  };

  migrate."test ignores non-registry patterns" = {
    expr = migrateLib.extractRegistryRefs "registry" ''
      { pkgs, lib, ... }:
      {
        foo = "registry";
        bar = pkgs.hello;
      }
    '';
    expected = [ ];
  };

  migrate."test handles deep nesting" = {
    expr = migrateLib.extractRegistryRefs "registry" ''
      registry.a.b.c.d.e
    '';
    expected = [ "a.b.c.d.e" ];
  };

  migrate."test extracts with custom registry name" = {
    expr = migrateLib.extractRegistryRefs "impRegistry" ''
      { impRegistry, ... }:
      { imports = [ impRegistry.home.alice ]; }
    '';
    expected = [ "home.alice" ];
  };

  # collectNixFiles tests
  migrate."test collects nix files recursively" = {
    expr =
      let
        files = migrateLib.collectNixFiles ./fixtures/migrate-test;
        # Just check count and that they're all .nix
        allNix = builtins.all (f: lib.hasSuffix ".nix" (toString f)) files;
      in
      {
        count = builtins.length files;
        allNix = allNix;
      };
    expected = {
      count = 3;
      allNix = true;
    };
  };

  # flattenRegistryPaths tests
  migrate."test flattens registry to list of paths" = {
    expr = migrateLib.flattenRegistryPaths {
      home = {
        __path = ./home;
        alice = ./alice;
      };
      modules = ./modules;
    };
    expected = [
      "home"
      "home.alice"
      "modules"
    ];
  };

  # isValidPath tests
  migrate."test isValidPath returns true for valid path" = {
    expr = migrateLib.isValidPath testRegistry "home.alice";
    expected = true;
  };

  migrate."test isValidPath returns true for nested path" = {
    expr = migrateLib.isValidPath testRegistry "modules.nixos.base";
    expected = true;
  };

  migrate."test isValidPath returns false for invalid path" = {
    expr = migrateLib.isValidPath testRegistry "users.alice";
    expected = false;
  };

  migrate."test isValidPath returns false for partial invalid path" = {
    expr = migrateLib.isValidPath testRegistry "home.unknown";
    expected = false;
  };

  # suggestNewPath tests
  migrate."test suggests new path based on leaf name" = {
    expr = migrateLib.suggestNewPath [ "home.alice" "home.bob" "modules.nixos" ] "users.alice";
    expected = "home.alice";
  };

  migrate."test returns null for ambiguous match" = {
    expr = migrateLib.suggestNewPath [ "a.foo" "b.foo" ] "x.foo";
    expected = null;
  };

  migrate."test returns null for no match" = {
    expr = migrateLib.suggestNewPath [ "home.alice" "home.bob" ] "users.charlie";
    expected = null;
  };

  # detectRenames integration tests
  migrate."test detectRenames finds broken refs" = {
    expr =
      let
        result = migrateLib.detectRenames {
          registry = testRegistry;
          paths = [ ./fixtures/migrate-test/outputs ];
        };
      in
      builtins.sort (a: b: a < b) result.brokenRefs;
    expected = [
      "mods.nixos"
      "users.alice"
      "users.bob"
    ];
  };

  migrate."test detectRenames suggests fixes" = {
    expr =
      let
        result = migrateLib.detectRenames {
          registry = testRegistry;
          paths = [ ./fixtures/migrate-test/outputs ];
        };
      in
      result.suggestions;
    expected = {
      "users.alice" = "home.alice";
      "users.bob" = "home.bob";
      "mods.nixos" = "modules.nixos";
    };
  };

  migrate."test detectRenames identifies affected files" = {
    expr =
      let
        result = migrateLib.detectRenames {
          registry = testRegistry;
          paths = [ ./fixtures/migrate-test/outputs ];
        };
      in
      builtins.length result.affectedFiles;
    expected = 2; # config-b.nix and mixed.nix have broken refs with suggestions
  };

  migrate."test detectRenames generates ast-grep commands" = {
    expr =
      let
        result = migrateLib.detectRenames {
          registry = testRegistry;
          paths = [ ./fixtures/migrate-test/outputs ];
        };
      in
      builtins.length result.commands > 0;
    expected = true;
  };

  migrate."test detectRenames with no broken refs" = {
    expr =
      let
        # Create inline content check - config-a.nix has only valid refs
        result = migrateLib.detectRenames {
          registry = testRegistry;
          paths = [ ./fixtures/migrate-test/outputs ];
        };
        # Check that home.alice and modules.nixos are NOT in brokenRefs
      in
      {
        homeAliceNotBroken = !(builtins.elem "home.alice" result.brokenRefs);
        modulesNixosNotBroken = !(builtins.elem "modules.nixos" result.brokenRefs);
      };
    expected = {
      homeAliceNotBroken = true;
      modulesNixosNotBroken = true;
    };
  };

  migrate."test script contains migration commands" = {
    expr =
      let
        result = migrateLib.detectRenames {
          registry = testRegistry;
          paths = [ ./fixtures/migrate-test/outputs ];
        };
      in
      lib.hasInfix "users.alice" result.script && lib.hasInfix "home.alice" result.script;
    expected = true;
  };

  migrate."test script shows commands without --apply" = {
    expr =
      let
        result = migrateLib.detectRenames {
          registry = testRegistry;
          paths = [ ./fixtures/migrate-test/outputs ];
        };
      in
      lib.hasInfix "Commands to apply:" result.script && lib.hasInfix "Run with --apply" result.script;
    expected = true;
  };

  migrate."test script has apply branch" = {
    expr =
      let
        result = migrateLib.detectRenames {
          registry = testRegistry;
          paths = [ ./fixtures/migrate-test/outputs ];
        };
      in
      lib.hasInfix ''if [[ "''${1:-}" == "--apply" ]]'' result.script;
    expected = true;
  };

  migrate."test affectedFiles are relative paths" = {
    expr =
      let
        result = migrateLib.detectRenames {
          registry = testRegistry;
          paths = [ ./fixtures/migrate-test/outputs ];
        };
        # All affected files should NOT start with /nix/store
        allRelative = builtins.all (f: !(lib.hasPrefix "/nix/store" f)) result.affectedFiles;
      in
      allRelative;
    expected = true;
  };

  migrate."test affectedFiles contain expected filenames" = {
    expr =
      let
        result = migrateLib.detectRenames {
          registry = testRegistry;
          paths = [ ./fixtures/migrate-test/outputs ];
        };
        hasConfigB = builtins.any (f: lib.hasSuffix "config-b.nix" f) result.affectedFiles;
        hasMixed = builtins.any (f: lib.hasSuffix "mixed.nix" f) result.affectedFiles;
      in
      {
        inherit hasConfigB hasMixed;
      };
    expected = {
      hasConfigB = true;
      hasMixed = true;
    };
  };
}
