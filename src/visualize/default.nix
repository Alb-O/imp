/**
  Visualization output for imp dependency graphs.

  Provides functions to format analyzed graphs for output.

  NOTE: For interactive HTML visualization, use:
  - The `imp-vis` app (requires configuring perSystem.imp.visualize)
  - Direct use of imp.graph library with wasmDistPath

  This module provides only JSON formatters that don't require WASM:
  - toJson: Full JSON with paths
  - toJsonMinimal: Minimal JSON without paths
*/
{ lib }:
let
  /**
    Convert graph to a JSON-serializable structure with full paths.

    # Arguments

    graph
    : Graph with nodes and edges from analyze functions.
  */
  toJson = graph: {
    nodes = map (n: n // { path = toString n.path; }) graph.nodes;
    edges = graph.edges;
  };

  /**
    Convert graph to JSON without paths (avoids store path issues with special chars).

    # Arguments

    graph
    : Graph with nodes and edges from analyze functions.
  */
  toJsonMinimal = graph: {
    nodes = map (
      n: { inherit (n) id type; } // lib.optionalAttrs (n ? strategy) { inherit (n) strategy; }
    ) graph.nodes;
    edges = graph.edges;
  };

in
{
  inherit
    toJson
    toJsonMinimal
    ;
}
