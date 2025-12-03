/**
  Visualization output for imp dependency graphs.

  Provides functions to format analyzed graphs for output:
  - toJson: Full JSON with paths
  - toJsonMinimal: Minimal JSON without paths
  - toHtml: Interactive HTML visualization
  - mkVisualizeScript: Shell script for CLI usage
*/
{ lib }:
let
  # Read the JavaScript template
  jsTemplate = builtins.readFile ./visualize-html.js;

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

  /**
    Generate interactive HTML visualization using force-graph library.

    Features: hover highlighting, cluster coloring, animated dashed directional edges, auto-fix on drag.

    # Arguments

    graph
    : Graph with nodes and edges from analyze functions.
  */
  toHtml =
    graph:
    let
      # Get leaf name (last segment of dotted path)
      leafName = id: lib.last (lib.splitString "." id);

      # Get cluster path - first two segments
      clusterPath =
        id:
        let
          parts = lib.splitString "." id;
        in
        if lib.length parts >= 2 then
          "${builtins.elemAt parts 0}.${builtins.elemAt parts 1}"
        else
          builtins.head parts;

      # Build edge lookups
      outgoingByNode = lib.foldl' (
        acc: e: acc // { ${e.from} = (acc.${e.from} or [ ]) ++ [ e.to ]; }
      ) { } graph.edges;

      incomingByNode = lib.foldl' (
        acc: e: acc // { ${e.to} = (acc.${e.to} or [ ]) ++ [ e.from ]; }
      ) { } graph.edges;

      # Node signature for merging
      nodeSignature =
        node:
        let
          cluster = clusterPath node.id;
          outs = lib.sort lib.lessThan (outgoingByNode.${node.id} or [ ]);
          ins = lib.sort lib.lessThan (incomingByNode.${node.id} or [ ]);
        in
        builtins.toJSON { inherit cluster outs ins; };

      nodesBySignature = lib.groupBy nodeSignature graph.nodes;

      # Create merged nodes
      mergedNodes = lib.mapAttrsToList (
        sig: nodes:
        let
          ids = map (n: n.id) nodes;
          names = map leafName ids;
          sortedNames = lib.sort lib.lessThan names;
          rep = builtins.head (lib.sort (a: b: a.id < b.id) nodes);
          cluster = clusterPath rep.id;
        in
        {
          id = rep.id;
          name = lib.concatStringsSep "\n" sortedNames;
          group = cluster;
          val = lib.length nodes; # Size based on merged count
        }
      ) nodesBySignature;

      # Build id -> merged id mapping
      idToMerged = lib.foldl' (
        acc: node:
        let
          origNodes =
            nodesBySignature.${nodeSignature (builtins.head (lib.filter (n: n.id == node.id) graph.nodes))};
          origIds = map (n: n.id) origNodes;
        in
        lib.foldl' (acc2: origId: acc2 // { ${origId} = node.id; }) acc origIds
      ) { } mergedNodes;

      # Remap and deduplicate edges
      remappedEdges = lib.unique (
        map (e: {
          source = idToMerged.${e.from};
          target = idToMerged.${e.to};
        }) graph.edges
      );

      finalEdges = lib.filter (e: e.source != e.target) remappedEdges;

      # JSON data for the graph
      graphJson = builtins.toJSON {
        nodes = mergedNodes;
        links = finalEdges;
      };

      # Cluster colors
      clusterColorsJson = builtins.toJSON {
        "modules.home" = "#1976d2";
        "modules.nixos" = "#7b1fa2";
        "outputs.nixosConfigurations" = "#e65100";
        "outputs.homeConfigurations" = "#2e7d32";
        "outputs.perSystem" = "#757575";
        "hosts.server" = "#c62828";
        "hosts.vm" = "#c62828";
        "hosts.workstation" = "#c62828";
        "users.alice" = "#00838f";
        "flake" = "#455a64";
        "flake.inputs" = "#78909c";
      };

      # Substitute placeholders in JS template
      jsCode =
        builtins.replaceStrings [ "/*GRAPH_DATA*/" "/*CLUSTER_COLORS*/" ] [ graphJson clusterColorsJson ]
          jsTemplate;
    in
    ''
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <title>imp Registry Visualization</title>
          <style>
            body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #2d2d2d; }
            #graph { width: 100vw; height: 100vh; }
            #info {
              position: absolute;
              top: 10px;
              left: 10px;
              background: rgba(45,45,45,0.95);
              color: #eee;
              padding: 12px 16px;
              border-radius: 8px;
              box-shadow: 0 2px 8px rgba(0,0,0,0.3);
              font-size: 13px;
              max-width: 300px;
              z-index: 100;
            }
            #info h3 { margin: 0 0 8px 0; font-size: 14px; color: #fff; }
            #info .cluster { color: #aaa; font-size: 11px; margin-bottom: 4px; }
            #info .nodes { white-space: pre-wrap; font-family: monospace; font-size: 12px; }
            #legend {
              position: absolute;
              bottom: 10px;
              left: 10px;
              background: rgba(45,45,45,0.95);
              color: #eee;
              padding: 10px 14px;
              border-radius: 8px;
              box-shadow: 0 2px 8px rgba(0,0,0,0.3);
              font-size: 11px;
              z-index: 100;
            }
            #legend h4 { margin: 0 0 6px 0; font-size: 12px; color: #fff; }
            .legend-item { display: flex; align-items: center; margin: 3px 0; }
            .legend-color { width: 12px; height: 12px; border-radius: 3px; margin-right: 8px; }
          </style>
          <script src="https://cdn.jsdelivr.net/npm/force-graph"></script>
        </head>
        <body>
          <div id="graph"></div>
          <div id="info">
            <h3>imp Registry</h3>
            <div class="hint">Hover over nodes to highlight connections</div>
          </div>
          <div id="legend">
            <h4>Clusters</h4>
          </div>

          <script>
      ${jsCode}
          </script>
        </body>
        </html>
    '';

  /**
    Build a shell script that outputs the graph in the requested format.

    Can be called two ways:

    1. With pre-computed graph (for flakeModule - fast, no runtime eval):
       mkVisualizeScript { pkgs, graph }

    2. With impSrc and nixpkgsFlake (standalone - runtime eval of arbitrary path):
       mkVisualizeScript { pkgs, impSrc, nixpkgsFlake }

    # Arguments

    pkgs
    : nixpkgs package set (for writeShellScript).

    graph
    : Pre-analyzed graph (optional, for pre-computed mode).

    impSrc
    : Path to imp source (optional, for standalone mode).

    nixpkgsFlake
    : Nixpkgs flake reference string (optional, for standalone mode).

    name
    : Script name (default: "imp-vis").
  */
  mkVisualizeScript =
    {
      pkgs,
      graph ? null,
      impSrc ? null,
      nixpkgsFlake ? null,
      name ? "imp-vis",
    }:
    let
      isStandalone = graph == null;

      # Pre-computed outputs for non-standalone mode
      jsonOutput = if isStandalone then "" else builtins.toJSON (toJsonMinimal graph);
      htmlOutput = if isStandalone then "" else toHtml graph;

      helpText = ''
        echo "Usage: ${name}${if isStandalone then " <path>" else ""} [--format=json|html]"
        echo ""
        echo "Visualize registry dependencies${if isStandalone then " for a directory" else ""}."
        echo ""
        echo "Options:"
        echo "  --format=json  Output JSON"
        echo "  --format=html  Output interactive HTML (default)"
        ${
          if isStandalone then
            ''
              echo ""
              echo "Examples:"
              echo "  ${name} ./nix > deps.html"
            ''
          else
            ""
        }
      '';

      # Output logic for pre-computed mode
      precomputedOutput = ''
                case "$FORMAT" in
                  json)
                    cat <<'GRAPH'
        ${jsonOutput}
        GRAPH
                    ;;
                  *)
                    cat <<'GRAPH'
        ${htmlOutput}
        GRAPH
                    ;;
                esac
      '';

      # Output logic for standalone mode (runtime nix eval)
      standaloneOutput = ''
        # Resolve to absolute path
        TARGET_PATH="$(cd "$TARGET_PATH" && pwd)"

        # Run the nix evaluation to generate the graph
        ${pkgs.nix}/bin/nix eval --raw --impure --expr '
          let
            lib = (builtins.getFlake "${nixpkgsFlake}").lib;
            visualizeLib = import ("${impSrc}" + "/src/visualize.nix") { inherit lib; };
            analyzeLib = import ("${impSrc}" + "/src/analyze.nix") { inherit lib; };
            registryLib = import ("${impSrc}" + "/src/registry.nix") { inherit lib; };

            targetPath = /. + "'"$TARGET_PATH"'";
            registry = registryLib.buildRegistry targetPath;
            graph = analyzeLib.analyzeRegistry { inherit registry; };

            formatted =
              if "'"$FORMAT"'" == "json" then
                builtins.toJSON (visualizeLib.toJsonMinimal graph)
              else
                visualizeLib.toHtml graph;
          in
          formatted
        '
      '';
    in
    pkgs.writeShellScript name ''
      set -euo pipefail

      ${lib.optionalString isStandalone "TARGET_PATH=\"\""}
      FORMAT="html"

      for arg in "$@"; do
        case "$arg" in
          --format=*) FORMAT="''${arg#--format=}" ;;
          --help|-h)
            ${helpText}
            exit 0
            ;;
          *)
            ${if isStandalone then ''TARGET_PATH="$arg"'' else ""}
            ;;
        esac
      done

      ${lib.optionalString isStandalone ''
        if [[ -z "$TARGET_PATH" ]]; then
          echo "Error: No path specified" >&2
          ${helpText}
          exit 1
        fi
      ''}

      ${if isStandalone then standaloneOutput else precomputedOutput}
    '';

in
{
  inherit
    toHtml
    toJson
    toJsonMinimal
    mkVisualizeScript
    ;
}
