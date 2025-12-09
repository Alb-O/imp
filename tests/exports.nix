# Tests for export collection and sink building
{
  lib,
  imp,
}:
let
  collectExports = imp.collectExports;
  buildExportSinks = imp.buildExportSinks;

  testPath = ./fixtures/exports-test;
in
{
  # Test basic export collection
  exports."collect finds __exports declarations" = {
    expr =
      let
        collected = collectExports testPath;
        hasNixosDesktop = collected ? "nixos.role.desktop.services";
        hasHmDesktop = collected ? "hm.role.desktop";
      in
      hasNixosDesktop && hasHmDesktop;
    expected = true;
  };

  exports."collected exports have source paths" = {
    expr =
      let
        collected = collectExports testPath;
        nixosServices = collected."nixos.role.desktop.services";
        allHaveSources = lib.all (e: e ? source) nixosServices;
      in
      allHaveSources;
    expected = true;
  };

  exports."collected exports track strategies" = {
    expr =
      let
        collected = collectExports testPath;
        nixosServices = collected."nixos.role.desktop.services";
        # Both should have merge strategy
        allMerge = lib.all (e: e.strategy == "merge") nixosServices;
      in
      allMerge;
    expected = true;
  };

  # Test merge strategies
  exports."merge strategy combines attrsets" = {
    expr =
      let
        collected = collectExports testPath;
        sinks = buildExportSinks {
          inherit lib collected;
          enableDebug = true;
        };
        # Should have both pipewire and greetd from different files in __module
        services = sinks.nixos.role.desktop.services.__module;
        hasBoth = services ? pipewire && services ? greetd;
      in
      hasBoth;
    expected = true;
  };

  exports."list-append strategy concatenates lists" = {
    expr =
      let
        collected = collectExports testPath;
        sinks = buildExportSinks {
          inherit lib collected;
          enableDebug = true;
        };
        packages = sinks.nixos.role.desktop.packages.__module;
        # Should have all packages from both files (order depends on file sort)
        hasAll =
          builtins.elem "htop" packages
          && builtins.elem "vim" packages
          && builtins.elem "git" packages
          && builtins.elem "tmux" packages;
        correctLength = builtins.length packages == 4;
      in
      hasAll && correctLength;
    expected = true;
  };

  exports."override strategy uses last value" = {
    expr =
      let
        collected = collectExports testPath;
        sinks = buildExportSinks {
          inherit lib collected;
          enableDebug = true;
        };
        # override-test2.nix comes after override-test.nix alphabetically
        result = sinks.test.override.__module;
      in
      result.foo == "second" && result.bar == "added";
    expected = true;
  };

  # Test metadata
  exports."debug mode includes metadata at leaf nodes" = {
    expr =
      let
        collected = collectExports testPath;
        sinks = buildExportSinks {
          inherit lib collected;
          enableDebug = true;
        };
        # Metadata is at the leaf (services), not intermediate (desktop)
        services = sinks.nixos.role.desktop.services;
        hasMeta = services ? __meta;
        hasContributors = services.__meta ? contributors;
      in
      hasMeta && hasContributors;
    expected = true;
  };

  exports."metadata lists all contributors for a sink" = {
    expr =
      let
        collected = collectExports testPath;
        sinks = buildExportSinks {
          inherit lib collected;
          enableDebug = true;
        };
        # Services sink has contributors from audio and wayland
        contributors = sinks.nixos.role.desktop.services.__meta.contributors;
        count = builtins.length contributors;
      in
      count >= 2;
    expected = true;
  };

  # Test sink defaults
  exports."sink defaults apply when no strategy specified" = {
    expr =
      let
        collected = collectExports testPath;
        sinks = buildExportSinks {
          inherit lib collected;
          sinkDefaults = {
            "nixos.*" = "merge";
          };
          enableDebug = true;
        };
        # Check strategy at a leaf node
        strategy = sinks.nixos.role.desktop.services.__meta.strategy;
      in
      strategy == "merge";
    expected = true;
  };

  # Test __functor pattern
  exports."__functor pattern works with exports" = {
    expr =
      let
        collected = collectExports testPath;
        hasHmExport = collected ? "hm.role.desktop";
      in
      hasHmExport;
    expected = true;
  };

  # Test multiple export keys from one file
  exports."multiple export keys from same file" = {
    expr =
      let
        collected = collectExports testPath;
        # wayland/base.nix exports to both services and programs
        hasServices = collected ? "nixos.role.desktop.services";
        hasPrograms = collected ? "nixos.role.desktop.programs";
      in
      hasServices && hasPrograms;
    expected = true;
  };

  # Test nested sink paths
  exports."sink paths create nested structure" = {
    expr =
      let
        collected = collectExports testPath;
        sinks = buildExportSinks {
          inherit lib collected;
          enableDebug = true;
        };
        # Should create nixos.role.desktop.services nested structure
        hasNixos = sinks ? nixos;
        hasRole = sinks.nixos ? role;
        hasDesktop = sinks.nixos.role ? desktop;
        hasServices = sinks.nixos.role.desktop ? services;
      in
      hasNixos && hasRole && hasDesktop && hasServices;
    expected = true;
  };

  # Test empty directory
  exports."empty directory returns empty attrset" = {
    expr =
      let
        collected = collectExports ./fixtures/hello;
      in
      collected == { };
    expected = true;
  };

  # Test single file path
  exports."single file path works" = {
    expr =
      let
        collected = collectExports ./fixtures/exports-test/features/packages.nix;
        hasPackages = collected ? "nixos.role.desktop.packages";
      in
      hasPackages;
    expected = true;
  };

  # Test shorthand export syntax (value only, no strategy)
  exports."shorthand export syntax works" = {
    expr =
      let
        collected = collectExports testPath;
        # wayland/base.nix uses shorthand for programs export
        programsExports = collected."nixos.role.desktop.programs";
        # Should have normalized to include strategy (null)
        allNormalized = lib.all (e: e ? value && e ? strategy) programsExports;
      in
      allNormalized;
    expected = true;
  };

  # Test convenience wrapper
  exports."exportSinks convenience wrapper works" = {
    expr =
      let
        lit = imp.withLib lib;
        sinks = lit.exportSinks { enableDebug = false; } testPath;
        hasDesktop = sinks ? nixos && sinks.nixos ? role;
      in
      hasDesktop;
    expected = true;
  };
}
