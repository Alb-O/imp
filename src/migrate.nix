/*
  Registry migration: detect renames and generate ast-grep commands to update references.

  When directories are renamed, registry paths change. This module:
  1. Scans files for registry.X.Y patterns
  2. Compares against current registry to find broken references
  3. Suggests mappings from old names to new names
  4. Generates ast-grep commands to fix all references

  Usage:
    migrate = import ./migrate.nix { inherit lib; };

    # Get migration commands
    migrate.detectRenames {
      registry = currentRegistry;
      files = [ ./nix/outputs ./nix/flake ];
    }
*/
{ lib }:
let
  inherit (lib)
    concatStringsSep
    filter
    flatten
    hasPrefix
    mapAttrsToList
    readFile
    splitString
    unique
    ;

  inherit (builtins)
    match
    readDir
    ;

  /*
    Extract all registry.X.Y.Z references from a file's content.
    Returns list of dotted paths like [ "home.alice" "modules.nixos" ]

    The `name` parameter is the registry attribute name to search for.
  */
  extractRegistryRefs =
    name: content:
    let
      # Match <name>.foo.bar patterns (simplified regex approach)
      # We'll use a line-by-line approach since Nix regex is limited
      lines = splitString "\n" content;
      pattern = "${name}.";

      extractFromLine =
        line:
        let
          # Find "<name>." and extract the path after it
          parts = splitString pattern line;
          extractPath =
            s:
            let
              # Take characters until we hit something that's not alphanumeric, _, or .
              m = match "([a-zA-Z_][a-zA-Z0-9_.]*)(.*)" s;
            in
            if m == null then null else builtins.head m;
        in
        if builtins.length parts < 2 then
          [ ]
        else
          filter (x: x != null) (map extractPath (builtins.tail parts));
    in
    unique (flatten (map extractFromLine lines));

  # Recursively collect all .nix files from a path.
  collectNixFiles =
    path:
    let
      entries = readDir path;
      process =
        name: type:
        let
          fullPath = path + "/${name}";
        in
        if type == "regular" && lib.hasSuffix ".nix" name then
          [ fullPath ]
        else if type == "directory" && !(hasPrefix "_" name) then
          collectNixFiles fullPath
        else
          [ ];
    in
    flatten (mapAttrsToList process entries);

  # Get all valid paths from a registry (flattened).
  flattenRegistryPaths =
    registry:
    let
      flatten =
        prefix: attrs:
        lib.foldlAttrs (
          acc: name: value:
          let
            key = if prefix == "" then name else "${prefix}.${name}";
          in
          if name == "__path" then
            acc
          else if lib.isAttrs value && !(value ? outPath) && !(lib.isDerivation value) then
            acc ++ [ key ] ++ flatten key value
          else
            acc ++ [ key ]
        ) [ ] attrs;
    in
    flatten "" registry;

  # Check if a registry path is valid (exists in the current registry).
  isValidPath =
    registry: path:
    let
      parts = splitString "." path;
      lookup =
        obj: ps:
        if ps == [ ] then
          true
        else if !(lib.isAttrs obj) then
          false
        else
          let
            head = builtins.head ps;
            tail = builtins.tail ps;
          in
          if obj ? ${head} then lookup obj.${head} tail else false;
    in
    lookup registry parts;

  /*
    Find the best matching new path for an old path.
    Uses simple heuristics: matching leaf name, similar structure.
  */
  suggestNewPath =
    validPaths: oldPath:
    let
      oldParts = splitString "." oldPath;
      oldLeaf = lib.last oldParts;

      # Find paths that end with the same leaf
      candidates = filter (p: lib.hasSuffix ".${oldLeaf}" p || p == oldLeaf) validPaths;

      # If we have exactly one match, use it
      # Otherwise return null (ambiguous)
    in
    if builtins.length candidates == 1 then builtins.head candidates else null;

  /*
    Detect renames by scanning files and comparing against registry.
    Returns: {
      brokenRefs = [ { file = ...; ref = "home.alice"; } ... ];
      suggestions = { "home.alice" = "users.alice"; ... };
      commands = [ "ast-grep ..." ... ];
    }

    The `astGrep` parameter is the path to the ast-grep binary.
    The `registryName` parameter is the attribute name uast-grep for the registry (default: "registry").
  */
  detectRenames =
    {
      registry,
      paths,
      astGrep ? "ast-grep",
      registryName ? "registry",
    }:
    let
      # Collect all nix files
      allFiles = unique (flatten (map collectNixFiles paths));

      # Extract refs from each file using the configured registry name
      fileRefs = map (f: {
        file = f;
        refs = extractRegistryRefs registryName (readFile f);
      }) allFiles;

      # Find broken refs
      allRefs = unique (flatten (map (x: x.refs) fileRefs));
      validPaths = flattenRegistryPaths registry;
      brokenRefs = filter (ref: !(isValidPath registry ref)) allRefs;

      # Suggest new paths
      suggestions = lib.listToAttrs (
        filter (x: x.value != null) (
          map (ref: {
            name = ref;
            value = suggestNewPath validPaths ref;
          }) brokenRefs
        )
      );

      # Generate ast-grep commands for each rename
      # Match the exact broken path and replace with the new path
      astGrepCommands = mapAttrsToList (
        old: new:
        "${astGrep} --lang nix --pattern '${registryName}.${old}' --rewrite '${registryName}.${new}'"
      ) suggestions;

      # Files that need updating (store paths)
      affectedFilesStore = unique (
        flatten (
          map (
            fr: if builtins.any (ref: suggestions ? ${ref}) fr.refs then [ (toString fr.file) ] else [ ]
          ) fileRefs
        )
      );

      # Convert store paths to relative paths for display
      # Store paths look like: /nix/store/xxx-source/nix/outputs/foo.nix
      # We want: nix/outputs/foo.nix
      toRelative =
        storePath:
        let
          # Find "-source/" in the path and take everything after
          parts = lib.splitString "-source/" storePath;
        in
        if builtins.length parts > 1 then builtins.elemAt parts 1 else storePath;

      affectedFiles = map toRelative affectedFilesStore;
    in
    {
      inherit brokenRefs suggestions affectedFiles;

      # Full commands with file paths
      commands =
        if affectedFiles == [ ] then
          [ ]
        else
          map (cmd: "${cmd} ${concatStringsSep " " affectedFiles}") astGrepCommands;

      # Shell script to run all migrations
      script = ''
        #!/usr/bin/env bash
        set -euo pipefail

        echo "Registry Migration"
        echo "=================="
        echo ""
        ${
          if suggestions == { } then
            ''
              echo "No renames detected!"
            ''
          else
            ''
              echo "Detected renames:"
              ${concatStringsSep "\n" (mapAttrsToList (old: new: ''echo "  ${old} -> ${new}"'') suggestions)}
              echo ""
              echo "Affected files:"
              ${concatStringsSep "\n" (map (f: ''echo "  ${f}"'') affectedFiles)}
              echo ""

              if [[ "''${1:-}" == "--apply" ]]; then
                echo "Applying fixes..."
                ${concatStringsSep "\n" (
                  map (cmd: "${cmd} --update-all ${concatStringsSep " " affectedFiles}") astGrepCommands
                )}
                echo "Done!"
              else
                echo "Commands to apply:"
                ${concatStringsSep "\n" (
                  map (
                    cmd:
                    let
                      escaped = builtins.replaceStrings [ "$" ] [ "\\$" ] cmd;
                    in
                    ''echo "  ${escaped} ${concatStringsSep " " affectedFiles}"''
                  ) astGrepCommands
                )}
                echo ""
                echo "Run with --apply to execute these commands."
              fi
            ''
        }
      '';
    };

in
{
  inherit
    extractRegistryRefs
    collectNixFiles
    flattenRegistryPaths
    isValidPath
    suggestNewPath
    detectRenames
    ;
}
