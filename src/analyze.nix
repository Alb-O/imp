/**
  Dependency graph analysis for imp.

  Provides functions to analyze config trees and registries, extracting
  dependency relationships for visualization.

  # Example

  Graph structure:

  ```nix
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
  ```

  Usage:

  ```nix
  # Analyze a registry to find all relationships
  imp.analyze.registry registry
  ```
*/
{ lib }:
let
  /**
    Scan a directory and build a list of all .nix files with their logical paths.

    # Example

    ```nix
    scanDir ./nix
    # => [ { path = /abs/path.nix; segments = ["programs" "git"]; } ... ]
    ```

    # Arguments

    root
    : Root directory to scan.
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

  /**
    Analyze a single configTree, returning nodes and edges.

    The path should be a directory. We scan it for .nix files and
    read each one to check for registry references.

    Note: We only collect refs from files directly in this directory,
    not from subdirectories (those are handled as separate nodes).

    # Arguments

    path
    : Directory path to analyze.

    id
    : Identifier for this config tree node.
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

      # Analyze each file and create a node + edges for it
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
          # File id: for default.nix use parent id, otherwise parent.filename
          fileId = if name == "default.nix" then id else "${id}.${lib.removeSuffix ".nix" name}";
        in
        {
          node = {
            id = fileId;
            inherit path;
            filePath = filePath;
            type = "file";
            parent = id;
          };
          edges = map (ref: {
            from = lib.removePrefix "registry." ref;
            to = fileId;
            type = "registry";
          }) uniqueRefs;
        };

      analyzedFiles = lib.mapAttrsToList (name: _: analyzeFile name) directFiles;

      allNodes = map (f: f.node) analyzedFiles;
      allEdges = lib.concatMap (f: f.edges) analyzedFiles;
    in
    {
      nodes = allNodes;
      edges = allEdges;
    };

  /**
    Analyze a mergeConfigTrees call.

    # Arguments

    id
    : Identifier for this merged tree.

    sources
    : List of { id, path } for each source tree.

    strategy
    : Merge strategy ("merge" or "override").
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

  /**
    Analyze an entire registry, discovering all modules and their relationships.

    This walks the registry structure, finds all configTrees, and analyzes
    each one for cross-references. Also generates hierarchical edges between
    parent and child nodes (e.g., modules -> modules.home).

    # Example

    ```nix
    analyzeRegistry { registry = myRegistry; }
    # => { nodes = [...]; edges = [...]; }
    ```

    # Arguments

    registry
    : Registry attrset to analyze.
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

      # Analyze each path that's a directory (configTree candidate) or file
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
          let
            content = builtins.readFile entry.path;
            matches = builtins.split "(registry\\.[a-zA-Z0-9_.]+)" content;
            refs = lib.filter (m: builtins.isList m) matches;
            refStrings = map (m: builtins.elemAt m 0) refs;
            uniqueRefs = lib.unique refStrings;
          in
          {
            nodes = [
              {
                inherit (entry) id path;
                type = "file";
              }
            ];
            edges = map (ref: {
              from = lib.removePrefix "registry." ref;
              to = entry.id;
              type = "registry";
            }) uniqueRefs;
          };

      results = map analyzeEntry allPaths;

      # Merge all results and deduplicate nodes by id
      rawNodes = lib.concatMap (r: r.nodes) results;
      allNodes = lib.attrValues (lib.foldl' (acc: node: acc // { ${node.id} = node; }) { } rawNodes);
      allEdges = lib.concatMap (r: r.edges) results;

      # Build set of known node IDs for validation
      knownIds = lib.listToAttrs (map (n: lib.nameValuePair n.id true) allNodes);

      # Resolve edge sources: convert registry.X.Y to just X.Y and validate
      resolvedEdges = map (
        edge:
        let
          sourceId = lib.removePrefix "registry." edge.from;
        in
        edge // { from = sourceId; }
      ) allEdges;

      # Filter registry edges to only those from known nodes, and deduplicate
      deduplicatedEdges = lib.unique resolvedEdges;
      validRegistryEdges = lib.filter (e: knownIds ? ${e.from}) deduplicatedEdges;
    in
    {
      nodes = allNodes;
      edges = validRegistryEdges;
    };

in
{
  inherit
    analyzeConfigTree
    analyzeMerge
    analyzeRegistry
    scanDir
    ;
}
