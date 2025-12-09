/**
  Collects __exports declarations from directory trees.
  Standalone implementation - no nixpkgs dependency, only builtins.

  Scans `.nix` files recursively for `__exports` attribute declarations and
  collects them, tracking source paths for debugging and conflict detection.

  Note: Only attrsets with `__exports` are collected. For functions that
  need to declare exports, use the `__functor` pattern:

  ```nix
  {
    __exports = {
      "nixos.role.desktop.services" = {
        value = { pipewire.enable = true; };
        strategy = "merge";
      };
    };
    __functor = _: { inputs, ... }: { __module = ...; };
  }
  ```

  # Example

  ```nix
  # Single path
  collectExports ./nix/registry
  # => {
  #   "nixos.role.desktop.services" = [
  #     {
  #       source = "/nix/registry/mod/nixos/features/desktop/audio.nix";
  #       value = { pipewire.enable = true; };
  #       strategy = "merge";
  #     }
  #   ];
  # }

  # Multiple paths (merged)
  collectExports [ ./nix/registry ./nix/features ]
  ```

  # Arguments

  pathOrPaths
  : Directory/file path, or list of paths, to scan for __exports declarations.
*/
let
  # Check if path should be excluded (starts with `_` in basename)
  isExcluded =
    path:
    let
      str = toString path;
      parts = builtins.filter (x: x != "") (builtins.split "/" str);
      basename = builtins.elemAt parts (builtins.length parts - 1);
    in
    builtins.substring 0 1 basename == "_";

  isAttrs = builtins.isAttrs;

  # Safely extract `__exports`, catching evaluation errors with `tryEval`
  safeExtractExports =
    value:
    let
      hasIt = builtins.tryEval (isAttrs value && value ? __exports && isAttrs value.__exports);
    in
    if hasIt.success && hasIt.value then
      let
        exports = value.__exports;
        forced = builtins.tryEval (builtins.deepSeq exports exports);
      in
      if forced.success then forced.value else { }
    else
      { };

  # Import a `.nix` file and extract `__exports` from attrsets only
  importAndExtract =
    path:
    let
      imported = builtins.tryEval (import path);
    in
    if !imported.success then
      { }
    else if isAttrs imported.value then
      safeExtractExports imported.value
    else
      # Functions are not called - use `__functor` pattern for functions with `__exports`
      { };

  # Normalize export entry: ensure it has value and optional strategy
  normalizeExportEntry =
    sinkKey: entry:
    if isAttrs entry && entry ? value then
      {
        value = entry.value;
        strategy = entry.strategy or null;
      }
    else
      # If just a raw value, wrap it
      {
        value = entry;
        strategy = null;
      };

  # Process exports from a single file
  processFileExports =
    sourcePath: exports:
    let
      sinkKeys = builtins.attrNames exports;
    in
    builtins.foldl' (
      acc: sinkKey:
      let
        entry = normalizeExportEntry sinkKey exports.${sinkKey};
        exportRecord = {
          source = toString sourcePath;
          inherit (entry) value strategy;
        };
      in
      acc
      // {
        ${sinkKey} = if acc ? ${sinkKey} then acc.${sinkKey} ++ [ exportRecord ] else [ exportRecord ];
      }
    ) { } sinkKeys;

  # Merge exports from multiple files
  mergeExports =
    acc: newExports:
    let
      allKeys = builtins.attrNames acc ++ builtins.attrNames newExports;
      uniqueKeys = builtins.foldl' (
        keys: key: if builtins.elem key keys then keys else keys ++ [ key ]
      ) [ ] allKeys;
    in
    builtins.foldl' (
      result: key:
      result
      // {
        ${key} = (acc.${key} or [ ]) ++ (newExports.${key} or [ ]);
      }
    ) { } uniqueKeys;

  # Process a single `.nix` file
  processFile =
    acc: path:
    let
      exports = importAndExtract path;
    in
    if exports == { } then acc else mergeExports acc (processFileExports path exports);

  # Process a directory recursively
  processDir =
    acc: path:
    let
      entries = builtins.readDir path;
      names = builtins.attrNames entries;

      process =
        acc: name:
        let
          entryPath = path + "/${name}";
          entryType = entries.${name};
          resolvedType = if entryType == "symlink" then builtins.readFileType entryPath else entryType;
        in
        if isExcluded entryPath then
          acc
        else if resolvedType == "regular" && builtins.match ".*\\.nix" name != null then
          processFile acc entryPath
        else if resolvedType == "directory" then
          let
            defaultPath = entryPath + "/default.nix";
            hasDefault = builtins.pathExists defaultPath;
          in
          if hasDefault then processFile acc defaultPath else processDir acc entryPath
        else
          acc;
    in
    builtins.foldl' process acc names;

  # Process a path (file or directory)
  processPath =
    acc: path:
    let
      rawPathType = builtins.readFileType path;
      pathType = if rawPathType == "symlink" then builtins.readFileType path else rawPathType;
    in
    if pathType == "regular" then
      processFile acc path
    else if pathType == "directory" then
      processDir acc path
    else
      acc;

  # Main: accepts path or list of paths
  collectExports =
    pathOrPaths:
    let
      paths = if builtins.isList pathOrPaths then pathOrPaths else [ pathOrPaths ];
      result = builtins.foldl' processPath { } paths;
    in
    result;

in
collectExports
