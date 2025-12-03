/*
  Dependency graph analysis for imp.

  Provides functions to analyze config trees and registries, extracting
  dependency relationships for visualization.

  Graph structure:
    {
      nodes = [
        { id = "modules.home.features.shell"; path = /path/to/shell; type = "configTree"; }
        { id = "modules.home.features.devShell"; path = /path/to/devShell; type = "configTree"; }
      ];
      edges = [
        { from = "modules.home.features.devShell"; to = "modules.home.features.shell"; type = "merge"; strategy = "merge"; }
        { from = "modules.home.features.devShell"; to = "modules.home.features.devTools"; type = "merge"; strategy = "merge"; }
      ];
    }

  Usage:
    # Analyze a registry to find all relationships
    imp.analyze.registry registry

    # Format as DOT
    imp.analyze.toDot graph

    # Format as JSON-compatible attrset
    imp.analyze.toJson graph
*/
{ lib }:
let
  /*
    Scan a directory and build a list of all .nix files with their logical paths.

    Returns: [ { path = /abs/path.nix; segments = ["programs" "git"]; } ... ]
  */
  scanDir =
    root:
    let
      scanInner =
        dir: prefix:
        let
          entries = builtins.readDir dir;

          processEntry =
            name: type:
            let
              path = dir + "/${name}";
              attrName = lib.removeSuffix ".nix" (lib.removeSuffix "_" name);
              newPrefix = prefix ++ [ attrName ];
            in
            if type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix" then
              [
                {
                  inherit path;
                  segments = newPrefix;
                }
              ]
            else if type == "directory" then
              let
                defaultPath = path + "/default.nix";
                hasDefault = builtins.pathExists defaultPath;
              in
              if hasDefault then
                [
                  {
                    path = defaultPath;
                    segments = newPrefix;
                  }
                ]
              else
                scanInner path newPrefix
            else
              [ ];

          filtered = lib.filterAttrs (name: _: !(lib.hasPrefix "_" name)) entries;
        in
        lib.concatLists (lib.mapAttrsToList processEntry filtered);
    in
    scanInner root [ ];

  /*
    Analyze a single configTree, returning nodes and edges.

    The path should be a directory. We scan it for .nix files and
    read each one to check for registry references.

    Note: We only collect refs from files directly in this directory,
    not from subdirectories (those are handled as separate nodes).
  */
  analyzeConfigTree =
    {
      path,
      id,
    }:
    let
      # Only look at files directly in this directory (not subdirs)
      entries = builtins.readDir path;

      directFiles = lib.filterAttrs (
        name: type: type == "regular" && lib.hasSuffix ".nix" name && !(lib.hasPrefix "_" name)
      ) entries;

      analyzeFile =
        name:
        let
          filePath = path + "/${name}";
          content = builtins.readFile filePath;
          # Find registry.foo.bar patterns
          matches = builtins.split "(registry\\.[a-zA-Z0-9_.]+)" content;
          refs = lib.filter (m: builtins.isList m) matches;
          refStrings = map (m: builtins.elemAt m 0) refs;
          uniqueRefs = lib.unique refStrings;
        in
        {
          path = filePath;
          registryRefs = uniqueRefs;
        };

      analyzedFiles = lib.mapAttrsToList (name: _: analyzeFile name) directFiles;

      # Collect all unique registry references from direct files only
      allRefs = lib.unique (lib.concatMap (f: f.registryRefs) analyzedFiles);

      # Convert refs to edges
      edges = map (ref: {
        from = id;
        to = lib.removePrefix "registry." ref;
        type = "registry";
      }) allRefs;
    in
    {
      nodes = [
        {
          inherit id path;
          type = "configTree";
          files = map (f: f.path) analyzedFiles;
        }
      ];
      inherit edges;
    };

  /*
    Analyze a mergeConfigTrees call.

    Arguments:
      - id: identifier for this merged tree
      - sources: list of { id, path } for each source tree
      - strategy: "merge" or "override"
  */
  analyzeMerge =
    {
      id,
      sources,
      strategy,
    }:
    let
      edges = map (src: {
        from = id;
        to = src.id;
        type = "merge";
        inherit strategy;
      }) sources;
    in
    {
      nodes = [
        {
          inherit id strategy;
          type = "mergedTree";
          sourceIds = map (s: s.id) sources;
        }
      ];
      inherit edges;
    };

  /*
    Analyze an entire registry, discovering all modules and their relationships.

    This walks the registry structure, finds all configTrees, and analyzes
    each one for cross-references.
  */
  analyzeRegistry =
    { registry }:
    let
      # Flatten registry to get all paths
      flattenWithPath =
        prefix: attrs:
        lib.concatLists (
          lib.mapAttrsToList (
            name: value:
            let
              newPrefix = if prefix == "" then name else "${prefix}.${name}";
            in
            if name == "__path" then
              [
                {
                  id = prefix;
                  path = value;
                }
              ]
            else if lib.isAttrs value && value ? __path then
              # Registry node with __path
              [
                {
                  id = newPrefix;
                  path = value.__path;
                }
              ]
              ++ flattenWithPath newPrefix value
            else if lib.isPath value || (lib.isAttrs value && value ? outPath) then
              [
                {
                  id = newPrefix;
                  path = value;
                }
              ]
            else if lib.isAttrs value then
              flattenWithPath newPrefix value
            else
              [ ]
          ) attrs
        );

      rawPaths = flattenWithPath "" registry;

      # Deduplicate by id (prefer entries with shorter ids for same path)
      allPaths = lib.attrValues (
        lib.foldl' (
          acc: entry: if acc ? ${entry.id} then acc else acc // { ${entry.id} = entry; }
        ) { } rawPaths
      );

      # Analyze each path that's a directory (configTree candidate)
      analyzeEntry =
        entry:
        let
          isDir = builtins.pathExists entry.path && builtins.readFileType entry.path == "directory";
        in
        if isDir then
          analyzeConfigTree {
            inherit (entry) path id;
          }
        else
          {
            nodes = [
              {
                inherit (entry) id path;
                type = "file";
              }
            ];
            edges = [ ];
          };

      results = map analyzeEntry allPaths;

      # Merge all results
      allNodes = lib.concatMap (r: r.nodes) results;
      allEdges = lib.concatMap (r: r.edges) results;

      # Resolve edge targets: convert registry.X.Y to just X.Y and validate
      resolvedEdges = map (
        edge:
        let
          targetId = lib.removePrefix "registry." edge.to;
        in
        edge // { to = targetId; }
      ) allEdges;

      # Filter edges to only those pointing to known nodes, and deduplicate
      knownIds = lib.listToAttrs (map (n: lib.nameValuePair n.id true) allNodes);
      deduplicatedEdges = lib.unique resolvedEdges;
      validEdges = lib.filter (e: knownIds ? ${e.to} || true) deduplicatedEdges;
    in
    {
      nodes = allNodes;
      edges = validEdges;
    };

  # Format graph as DOT (Graphviz) format.
  toDot =
    graph:
    let
      # Escape quotes in strings for DOT
      escape = s: lib.replaceStrings [ "\"" "\n" ] [ "\\\"" "\\n" ] s;

      # Node styling based on type
      nodeStyle =
        node:
        let
          baseLabel = escape node.id;
          style =
            if node.type == "mergedTree" then
              ''shape=box,style=filled,fillcolor=lightblue,label="${baseLabel}\n[${node.strategy}]"''
            else if node.type == "configTree" then
              ''shape=box,style=filled,fillcolor=lightyellow,label="${baseLabel}"''
            else
              ''shape=ellipse,label="${baseLabel}"'';
        in
        ''"${escape node.id}" [${style}];'';

      # Edge styling based on type
      edgeStyle =
        edge:
        let
          style =
            if edge.type == "merge" then
              ''style=bold,color=blue,label="${edge.strategy or ""}"''
            else if edge.type == "registry" then
              ''style=dashed,color=gray''
            else
              "";
        in
        ''"${escape edge.from}" -> "${escape edge.to}"''
        + lib.optionalString (style != "") " [${style}]"
        + ";";

      nodeLines = map nodeStyle graph.nodes;
      edgeLines = map edgeStyle graph.edges;
    in
    ''
      digraph imp_registry {
        rankdir=LR;
        node [fontname="sans-serif"];
        edge [fontname="sans-serif"];

        ${lib.concatStringsSep "\n  " nodeLines}

        ${lib.concatStringsSep "\n  " edgeLines}
      }
    '';

  # Format graph as ASCII tree (simplified view).
  toAsciiTree =
    graph:
    let
      # Build adjacency list
      adjacency = lib.foldl' (
        acc: edge:
        acc
        // {
          ${edge.from} = (acc.${edge.from} or [ ]) ++ [
            {
              to = edge.to;
              type = edge.type;
              strategy = edge.strategy or null;
            }
          ];
        }
      ) { } graph.edges;

      # Find root nodes (nodes with no incoming edges)
      hasIncoming = lib.listToAttrs (map (e: lib.nameValuePair e.to true) graph.edges);
      roots = lib.filter (n: !(hasIncoming ? ${n.id})) graph.nodes;

      # Render a node and its children
      renderNode =
        indent: visited: node:
        let
          prefix = lib.concatStrings (lib.genList (_: "  ") indent);
          children = adjacency.${node.id} or [ ];
          nodeType =
            if node.type == "mergedTree" then
              "[merged:${node.strategy}]"
            else if node.type == "configTree" then
              "[tree]"
            else
              "[file]";

          childLines = lib.concatMapStrings (
            child:
            let
              edgeType = if child.type == "merge" then "─(merge)─▶ " else "─────────▶ ";
              childNode = lib.findFirst (n: n.id == child.to) null graph.nodes;
            in
            if childNode == null || lib.elem child.to visited then
              "${prefix}├${edgeType}${child.to} (circular or external)\n"
            else
              "${prefix}├${edgeType}\n" + renderNode (indent + 1) (visited ++ [ node.id ]) childNode
          ) children;
        in
        "${prefix}${node.id} ${nodeType}\n${childLines}";

      rootLines = lib.concatMapStrings (renderNode 0 [ ]) roots;
    in
    if roots == [ ] then
      "No root nodes found (circular dependencies or empty graph)\n"
    else
      "imp Registry Dependency Graph\n${
        "=" + lib.concatStrings (lib.genList (_: "=") 30)
      }\n\n${rootLines}";

  # Convert graph to a JSON-serializable structure.
  toJson = graph: {
    nodes = map (n: n // { path = toString n.path; }) graph.nodes;
    edges = graph.edges;
  };

  # Convert graph to JSON without paths (avoids store path issues with special chars).
  toJsonMinimal = graph: {
    nodes = map (
      n: { inherit (n) id type; } // lib.optionalAttrs (n ? strategy) { inherit (n) strategy; }
    ) graph.nodes;
    edges = graph.edges;
  };

  /*
    Build a shell script that outputs the graph in the requested format.

    Can be called two ways:

    1. With pre-computed graph (for flakeModule - fast, no runtime eval):
       mkVisualizeScript { pkgs, graph }

    2. With impSrc and nixpkgsFlake (standalone - runtime eval of arbitrary path):
       mkVisualizeScript { pkgs, impSrc, nixpkgsFlake }

    Arguments:
      - pkgs: nixpkgs package set (for writeShellScript)
      - graph: pre-analyzed graph (optional, for pre-computed mode)
      - impSrc: path to imp source (optional, for standalone mode)
      - nixpkgsFlake: nixpkgs flake reference string (optional, for standalone mode)
      - name: script name (default: "imp-vis")

    Returns: a derivation for the shell script
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
      dotOutput = if isStandalone then "" else toDot graph;
      asciiOutput = if isStandalone then "" else toAsciiTree graph;
      jsonOutput = if isStandalone then "" else builtins.toJSON (toJsonMinimal graph);

      helpText = ''
        echo "Usage: ${name}${if isStandalone then " <path>" else ""} [--format=dot|ascii|json]"
        echo ""
        echo "Visualize registry dependencies${if isStandalone then " for a directory" else ""}."
        echo ""
        echo "Options:"
        echo "  --format=dot    Output Graphviz DOT format (default)"
        echo "  --format=ascii  Output ASCII tree"
        echo "  --format=json   Output JSON"
        ${
          if isStandalone then
            ''
              echo ""
              echo "Examples:"
              echo "  ${name} ./nix > deps.dot"
              echo "  ${name} ./nix --format=ascii"
            ''
          else
            ""
        }
      '';

      # Output logic for pre-computed mode
      precomputedOutput = ''
                case "$FORMAT" in
                  ascii)
                    cat <<'GRAPH'
        ${asciiOutput}
        GRAPH
                    ;;
                  json)
                    cat <<'GRAPH'
        ${jsonOutput}
        GRAPH
                    ;;
                  *)
                    cat <<'GRAPH'
        ${dotOutput}
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
            analyzeLib = import ("${impSrc}" + "/src/analyze.nix") { inherit lib; };
            registryLib = import ("${impSrc}" + "/src/registry.nix") { inherit lib; };

            targetPath = /. + "'"$TARGET_PATH"'";
            registry = registryLib.buildRegistry targetPath;
            graph = analyzeLib.analyzeRegistry { inherit registry; };

            formatted =
              if "'"$FORMAT"'" == "ascii" then
                analyzeLib.toAsciiTree graph
              else if "'"$FORMAT"'" == "json" then
                builtins.toJSON (analyzeLib.toJsonMinimal graph)
              else
                analyzeLib.toDot graph;
          in
          formatted
        '
      '';
    in
    pkgs.writeShellScript name ''
      set -euo pipefail

      ${lib.optionalString isStandalone "TARGET_PATH=\"\""}
      FORMAT="dot"

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
    analyzeConfigTree
    analyzeMerge
    analyzeRegistry
    scanDir
    toDot
    toAsciiTree
    toJson
    toJsonMinimal
    mkVisualizeScript
    ;
}
