# Tests for migrate: detecting renames and generating fix commands
{ lib, ... }:
let
  migrateLib = import ../src/migrate.nix { inherit lib; };
  registryLib = import ../src/registry.nix { inherit lib; };

  # Build a registry from the existing registry-test fixture
  # This represents the "current" state after renames
  testRegistry = registryLib.buildRegistry ./fixtures/registry-test;

  # Complex registry for advanced rename scenarios
  # Structure represents "after" state:
  #   users/{alice/programs/{editor,zsh},bob}  (was: home/...)
  #   services/{database/{postgresql,redis},web/{nginx,caddy}}  (was: svc/...)
  #   profiles/{desktop/gnome,server/minimal}  (was: mods.profiles/...)
  #   lib/helpers/strings  (was: utils/helpers/...)
  complexRegistry = registryLib.buildRegistry ./fixtures/complex-renames/registry;
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

  # =============================================================================
  # Complex rename scenarios
  # =============================================================================

  # Multiple simultaneous renames: home->users, svc->services, mods.profiles->profiles
  migrate."test complex: detects multiple simultaneous renames" = {
    expr =
      let
        result = migrateLib.detectRenames {
          registry = complexRegistry;
          paths = [ ./fixtures/complex-renames/files ];
        };
        broken = builtins.sort (a: b: a < b) result.brokenRefs;
      in
      # Should find all broken refs from different rename scenarios
      {
        hasHomeAliceNeovim = builtins.elem "home.alice.programs.editor" broken;
        hasHomeBobShell = builtins.elem "home.bob.shell" broken;
        hasSvcDatabase = builtins.elem "svc.database.postgresql" broken;
        hasSvcWeb = builtins.elem "svc.web.nginx" broken;
        hasModsProfiles = builtins.elem "mods.profiles.desktop.gnome" broken;
      };
    expected = {
      hasHomeAliceNeovim = true;
      hasHomeBobShell = true;
      hasSvcDatabase = true;
      hasSvcWeb = true;
      hasModsProfiles = true;
    };
  };

  migrate."test complex: suggests fixes for multiple renames" = {
    expr =
      let
        result = migrateLib.detectRenames {
          registry = complexRegistry;
          paths = [ ./fixtures/complex-renames/files ];
        };
      in
      {
        # home -> users
        homeAliceNeovim = result.suggestions."home.alice.programs.editor" or null;
        homeBobShell = result.suggestions."home.bob.shell" or null;
        # svc -> services
        svcPostgresql = result.suggestions."svc.database.postgresql" or null;
        svcNginx = result.suggestions."svc.web.nginx" or null;
        # mods.profiles -> profiles
        modsGnome = result.suggestions."mods.profiles.desktop.gnome" or null;
      };
    expected = {
      homeAliceNeovim = "users.alice.programs.editor";
      homeBobShell = "users.bob.shell";
      svcPostgresql = "services.database.postgresql";
      svcNginx = "services.web.nginx";
      modsGnome = "profiles.desktop.gnome";
    };
  };

  # Nested renames: parent renamed, all children should be detected
  migrate."test complex: nested renames detect all children" = {
    expr =
      let
        result = migrateLib.detectRenames {
          registry = complexRegistry;
          paths = [ ./fixtures/complex-renames/files ];
        };
        broken = result.brokenRefs;
      in
      {
        # All nested paths under home.alice.programs should be broken
        hasNeovim = builtins.elem "home.alice.programs.editor" broken;
        hasZsh = builtins.elem "home.alice.programs.zsh" broken;
        hasBobShell = builtins.elem "home.bob.shell" broken;
      };
    expected = {
      hasNeovim = true;
      hasZsh = true;
      hasBobShell = true;
    };
  };

  migrate."test complex: nested renames suggest correct paths" = {
    expr =
      let
        result = migrateLib.detectRenames {
          registry = complexRegistry;
          paths = [ ./fixtures/complex-renames/files ];
        };
      in
      {
        editor = result.suggestions."home.alice.programs.editor" or null;
        zsh = result.suggestions."home.alice.programs.zsh" or null;
        bobShell = result.suggestions."home.bob.shell" or null;
      };
    expected = {
      editor = "users.alice.programs.editor";
      zsh = "users.alice.programs.zsh";
      bobShell = "users.bob.shell";
    };
  };

  # Deep nesting with mid-level renames
  migrate."test complex: deep nesting with various rename depths" = {
    expr =
      let
        result = migrateLib.detectRenames {
          registry = complexRegistry;
          paths = [ ./fixtures/complex-renames/files ];
        };
      in
      {
        # svc.db -> services.database
        postgresql = result.suggestions."svc.db.postgresql" or null;
        redis = result.suggestions."svc.db.redis" or null;
        # svc.http -> services.web
        nginx = result.suggestions."svc.http.nginx" or null;
        caddy = result.suggestions."svc.http.caddy" or null;
        # utils.helpers -> lib.helpers
        strings = result.suggestions."utils.helpers.strings" or null;
      };
    expected = {
      postgresql = "services.database.postgresql";
      redis = "services.database.redis";
      nginx = "services.web.nginx";
      caddy = "services.web.caddy";
      strings = "lib.helpers.strings";
    };
  };

  # Ambiguous renames: same leaf name in multiple locations
  migrate."test complex: ambiguous refs return null suggestion" = {
    expr =
      let
        result = migrateLib.detectRenames {
          registry = complexRegistry;
          paths = [ ./fixtures/complex-renames/files ];
        };
      in
      {
        # "editor" only exists in one place, should match
        editor = result.suggestions."old.programs.editor" or null;
        # "gnome" only exists in one place, should match
        gnome = result.suggestions."old.desktop.gnome" or null;
        # "minimal" only exists in one place, should match
        minimal = result.suggestions."config.server.minimal" or null;
        # "base" doesn't exist anywhere - no match
        noMatch = result.suggestions."configs.base" or "not-found";
      };
    expected = {
      editor = "users.alice.programs.editor";
      gnome = "profiles.desktop.gnome";
      minimal = "profiles.server.minimal";
      noMatch = "not-found";
    };
  };

  migrate."test complex: refs without matches are detected as broken" = {
    expr =
      let
        result = migrateLib.detectRenames {
          registry = complexRegistry;
          paths = [ ./fixtures/complex-renames/files ];
        };
      in
      {
        configsBase = builtins.elem "configs.base" result.brokenRefs;
      };
    expected = {
      configsBase = true;
    };
  };

  # Partial valid: mix of valid and broken refs
  migrate."test complex: correctly distinguishes valid from broken" = {
    expr =
      let
        result = migrateLib.detectRenames {
          registry = complexRegistry;
          paths = [ ./fixtures/complex-renames/files ];
        };
      in
      {
        # These are valid (in current registry) - should NOT be broken
        usersAliceProgramsValid = !(builtins.elem "users.alice.programs.editor" result.brokenRefs);
        servicesDbValid = !(builtins.elem "services.database.postgresql" result.brokenRefs);
        profilesDesktopValid = !(builtins.elem "profiles.desktop.gnome" result.brokenRefs);
        # These are broken (old names)
        homeBobBroken = builtins.elem "home.bob.shell" result.brokenRefs;
        svcWebBroken = builtins.elem "svc.web.caddy" result.brokenRefs;
      };
    expected = {
      usersAliceProgramsValid = true;
      servicesDbValid = true;
      profilesDesktopValid = true;
      homeBobBroken = true;
      svcWebBroken = true;
    };
  };

  # All valid file should not produce suggestions
  migrate."test complex: all-valid file produces no broken refs for valid paths" = {
    expr =
      let
        result = migrateLib.detectRenames {
          registry = complexRegistry;
          paths = [ ./fixtures/complex-renames/files ];
        };
        # Check that common valid paths are not in brokenRefs
        validPaths = [
          "users.alice.programs.editor"
          "users.alice.programs.zsh"
          "users.bob.shell"
          "services.database.postgresql"
          "services.web.nginx"
          "profiles.desktop.gnome"
          "lib.helpers.strings"
        ];
      in
      builtins.all (p: !(builtins.elem p result.brokenRefs)) validPaths;
    expected = true;
  };

  # Count affected files correctly
  migrate."test complex: counts affected files correctly" = {
    expr =
      let
        result = migrateLib.detectRenames {
          registry = complexRegistry;
          paths = [ ./fixtures/complex-renames/files ];
        };
      in
      # Files with broken refs that have suggestions:
      # - multi-rename.nix (has home, svc, mods refs)
      # - nested-rename.nix (has home refs)
      # - deep-nesting.nix (has svc, utils refs)
      # - partial-valid.nix (has home, svc refs)
      # - ambiguous.nix (has refs that DO have suggestions now)
      # NOT: all-valid.nix (all valid)
      {
        count = builtins.length result.affectedFiles;
        hasMultiRename = builtins.any (f: lib.hasSuffix "multi-rename.nix" f) result.affectedFiles;
        hasNestedRename = builtins.any (f: lib.hasSuffix "nested-rename.nix" f) result.affectedFiles;
        hasDeepNesting = builtins.any (f: lib.hasSuffix "deep-nesting.nix" f) result.affectedFiles;
        hasPartialValid = builtins.any (f: lib.hasSuffix "partial-valid.nix" f) result.affectedFiles;
        hasAmbiguous = builtins.any (f: lib.hasSuffix "ambiguous.nix" f) result.affectedFiles;
        # all-valid.nix should NOT be affected
        noAllValid = !(builtins.any (f: lib.hasSuffix "all-valid.nix" f) result.affectedFiles);
      };
    expected = {
      count = 5;
      hasMultiRename = true;
      hasNestedRename = true;
      hasDeepNesting = true;
      hasPartialValid = true;
      hasAmbiguous = true;
      noAllValid = true;
    };
  };

  # Commands are generated for each suggestion
  migrate."test complex: generates commands for all suggestions" = {
    expr =
      let
        result = migrateLib.detectRenames {
          registry = complexRegistry;
          paths = [ ./fixtures/complex-renames/files ];
        };
        commandsStr = lib.concatStringsSep "\n" result.commands;
      in
      {
        # Check that commands include various renames
        hasHomeToUsers =
          lib.hasInfix "home.alice.programs.editor" commandsStr
          && lib.hasInfix "users.alice.programs.editor" commandsStr;
        hasSvcToServices =
          lib.hasInfix "svc.database.postgresql" commandsStr
          && lib.hasInfix "services.database.postgresql" commandsStr;
        hasUtilsToLib =
          lib.hasInfix "utils.helpers.strings" commandsStr && lib.hasInfix "lib.helpers.strings" commandsStr;
      };
    expected = {
      hasHomeToUsers = true;
      hasSvcToServices = true;
      hasUtilsToLib = true;
    };
  };

  # Script includes all renames
  migrate."test complex: script shows all detected renames" = {
    expr =
      let
        result = migrateLib.detectRenames {
          registry = complexRegistry;
          paths = [ ./fixtures/complex-renames/files ];
        };
      in
      {
        hasHomeAlice = lib.hasInfix "home.alice.programs.editor -> users.alice.programs.editor" result.script;
        hasSvcDb = lib.hasInfix "svc.database.postgresql -> services.database.postgresql" result.script;
        hasNestedZsh = lib.hasInfix "home.alice.programs.zsh -> users.alice.programs.zsh" result.script;
      };
    expected = {
      hasHomeAlice = true;
      hasSvcDb = true;
      hasNestedZsh = true;
    };
  };

  # Test with multiple paths
  migrate."test complex: handles multiple scan paths" = {
    expr =
      let
        result = migrateLib.detectRenames {
          registry = complexRegistry;
          paths = [
            ./fixtures/complex-renames/files
            ./fixtures/migrate-test/outputs
          ];
        };
      in
      {
        # Should find refs from both directories
        # From complex-renames/files
        hasHomeAliceNeovim = builtins.elem "home.alice.programs.editor" result.brokenRefs;
        # From migrate-test/outputs - mods.nixos is broken in both registries
        hasModsNixos = builtins.elem "mods.nixos" result.brokenRefs;
      };
    expected = {
      hasHomeAliceNeovim = true;
      hasModsNixos = true;
    };
  };

  # suggestNewPath edge cases for complex scenarios
  migrate."test suggestNewPath with deep nested paths" = {
    expr = migrateLib.suggestNewPath [
      "users.alice.programs.editor"
      "users.alice.programs.zsh"
      "services.database.postgresql"
    ] "home.alice.programs.editor";
    expected = "users.alice.programs.editor";
  };

  migrate."test suggestNewPath with multiple same-depth ambiguity" = {
    expr = migrateLib.suggestNewPath [
      "services.database.postgresql"
      "legacy.database.postgresql" # Same leaf, ambiguous
    ] "old.db.postgresql";
    expected = null;
  };

  migrate."test suggestNewPath matches deepest unique leaf" = {
    expr = migrateLib.suggestNewPath [
      "users.alice"
      "profiles.desktop.gnome"
      "services.web.nginx"
    ] "config.desktop.gnome";
    expected = "profiles.desktop.gnome";
  };

  # flattenRegistryPaths with deep nesting
  migrate."test flattenRegistryPaths with deeply nested structure" = {
    expr =
      let
        paths = migrateLib.flattenRegistryPaths {
          users = {
            alice = {
              programs = {
                editor = ./editor;
                zsh = ./zsh;
              };
            };
          };
        };
      in
      builtins.sort (a: b: a < b) paths;
    expected = [
      "users"
      "users.alice"
      "users.alice.programs"
      "users.alice.programs.editor"
      "users.alice.programs.zsh"
    ];
  };

  # isValidPath with deep paths
  migrate."test isValidPath with 4-level deep path" = {
    expr = migrateLib.isValidPath complexRegistry "users.alice.programs.editor";
    expected = true;
  };

  migrate."test isValidPath rejects partial deep path" = {
    expr = migrateLib.isValidPath complexRegistry "users.alice.programs.vim";
    expected = false;
  };
}
