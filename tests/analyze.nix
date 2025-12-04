# Tests for analyze module
{ lib, imp, ... }:
let
  analyze = (imp.withLib lib).analyze;
  registryLib = import ../src/registry.nix { inherit lib; };

  # Use registry-test fixture for testing
  testRegistryPath = ./fixtures/registry-test;
  testRegistry = registryLib.buildRegistry testRegistryPath;
in
{
  analyze."test analyzeRegistry returns nodes and edges" =
    let
      result = analyze.analyzeRegistry { registry = testRegistry; };
    in
    {
      expr = builtins.isAttrs result && result ? nodes && result ? edges;
      expected = true;
    };

  analyze."test analyzeRegistry finds all registry entries" =
    let
      result = analyze.analyzeRegistry { registry = testRegistry; };
      nodeIds = map (n: n.id) result.nodes;
    in
    {
      # Should find home, home.alice, home.bob, etc.
      expr = builtins.elem "home.alice" nodeIds && builtins.elem "modules.nixos.base" nodeIds;
      expected = true;
    };

  analyze."test toHtml produces valid HTML output" =
    let
      result = analyze.analyzeRegistry { registry = testRegistry; };
      html = analyze.toHtml result;
      trimmed = lib.trim html;
    in
    {
      # Check for doctype (case-insensitive) - formatter may change case
      expr = lib.hasPrefix "<!doctype html>" (lib.toLower trimmed);
      expected = true;
    };

  analyze."test toJson produces serializable structure" =
    let
      result = analyze.analyzeRegistry { registry = testRegistry; };
      json = analyze.toJson result;
    in
    {
      expr = builtins.isAttrs json && json ? nodes && json ? edges;
      expected = true;
    };

  analyze."test nodes have required attributes" =
    let
      result = analyze.analyzeRegistry { registry = testRegistry; };
      firstNode = builtins.head result.nodes;
    in
    {
      expr = firstNode ? id && firstNode ? type;
      expected = true;
    };

  analyze."test scanDir finds nix files" =
    let
      files = analyze.scanDir ./fixtures/tree-test;
      paths = map (f: builtins.baseNameOf (toString f.path)) files;
    in
    {
      expr = builtins.elem "foo.nix" paths;
      expected = true;
    };
}
