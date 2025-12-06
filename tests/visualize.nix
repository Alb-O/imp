# Tests for visualize module (JSON formatters only)
#
# NOTE: HTML visualization tests are in imp.graph.
# This module only provides toJson and toJsonMinimal which don't require WASM.
{ lib, imp, ... }:
let
  visualize = import ../src/visualize { inherit lib; };
  registryLib = import ../src/registry.nix { inherit lib; };
  analyze = (imp.withLib lib).analyze;

  # Use registry-test fixture for testing
  testRegistryPath = ./fixtures/registry-test;
  testRegistry = registryLib.buildRegistry testRegistryPath;

  # Sample graph for testing visualization functions
  sampleGraph = {
    nodes = [
      {
        id = "modules.home.shell";
        path = /test/path/shell;
        type = "configTree";
      }
      {
        id = "modules.home.devTools";
        path = /test/path/devTools;
        type = "configTree";
      }
      {
        id = "hosts.workstation";
        path = /test/path/workstation;
        type = "configTree";
      }
    ];
    edges = [
      {
        from = "modules.home.shell";
        to = "hosts.workstation";
        type = "import";
      }
      {
        from = "modules.home.devTools";
        to = "hosts.workstation";
        type = "import";
      }
    ];
  };

  # Minimal graph with single node
  minimalGraph = {
    nodes = [
      {
        id = "single.node";
        path = /test/single;
        type = "file";
      }
    ];
    edges = [ ];
  };

  # Graph with merge strategy
  mergeGraph = {
    nodes = [
      {
        id = "modules.home.base";
        path = /test/base;
        type = "configTree";
        strategy = "merge";
      }
      {
        id = "modules.home.extended";
        path = /test/extended;
        type = "configTree";
        strategy = "override";
      }
    ];
    edges = [
      {
        from = "modules.home.base";
        to = "modules.home.extended";
        type = "merge";
        strategy = "merge";
      }
    ];
  };
in
{
  # toJson tests
  toJson."test returns nodes and edges" = {
    expr = visualize.toJson sampleGraph;
    expected = {
      nodes = [
        {
          id = "modules.home.shell";
          path = "/test/path/shell";
          type = "configTree";
        }
        {
          id = "modules.home.devTools";
          path = "/test/path/devTools";
          type = "configTree";
        }
        {
          id = "hosts.workstation";
          path = "/test/path/workstation";
          type = "configTree";
        }
      ];
      edges = sampleGraph.edges;
    };
  };

  toJson."test converts paths to strings" = {
    expr =
      let
        result = visualize.toJson minimalGraph;
      in
      builtins.isString (builtins.head result.nodes).path;
    expected = true;
  };

  toJson."test preserves edge structure" = {
    expr = (visualize.toJson sampleGraph).edges;
    expected = sampleGraph.edges;
  };

  # toJsonMinimal tests
  toJsonMinimal."test returns only id and type" = {
    expr = visualize.toJsonMinimal minimalGraph;
    expected = {
      nodes = [
        {
          id = "single.node";
          type = "file";
        }
      ];
      edges = [ ];
    };
  };

  toJsonMinimal."test excludes path from nodes" = {
    expr =
      let
        result = visualize.toJsonMinimal sampleGraph;
        firstNode = builtins.head result.nodes;
      in
      firstNode ? path;
    expected = false;
  };

  toJsonMinimal."test preserves strategy when present" = {
    expr =
      let
        result = visualize.toJsonMinimal mergeGraph;
        nodeWithStrategy = builtins.head (lib.filter (n: n.id == "modules.home.base") result.nodes);
      in
      nodeWithStrategy.strategy;
    expected = "merge";
  };

  toJsonMinimal."test excludes strategy when absent" = {
    expr =
      let
        result = visualize.toJsonMinimal sampleGraph;
        firstNode = builtins.head result.nodes;
      in
      firstNode ? strategy;
    expected = false;
  };

  # Integration with analyze module
  integration."test toJson works with analyzeRegistry output" = {
    expr =
      let
        graph = analyze.analyzeRegistry { registry = testRegistry; };
        json = visualize.toJson graph;
      in
      builtins.isAttrs json && json ? nodes && json ? edges;
    expected = true;
  };

  integration."test toJsonMinimal works with analyzeRegistry output" = {
    expr =
      let
        graph = analyze.analyzeRegistry { registry = testRegistry; };
        json = visualize.toJsonMinimal graph;
      in
      builtins.isAttrs json && json ? nodes && json ? edges;
    expected = true;
  };
}
