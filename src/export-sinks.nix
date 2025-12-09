/**
  Build sinks from collected exports with merge strategy support.

  Takes the output from collectExports and produces materialized sinks
  by applying merge strategies. Each sink becomes a usable Nix value
  (typically a module or attrset).

  # Merge Strategies

  - `merge`: Deep merge using lib.recursiveUpdate (last wins for primitives)
  - `override`: Last writer completely replaces earlier values
  - `list-append`: Concatenate lists (error if non-list)
  - `mkMerge`: For module functions, wraps in { imports = [...]; }. For
    plain attrsets, uses lib.mkMerge for module system semantics.

  # Example

  ```nix
  buildExportSinks {
    lib = nixpkgs.lib;
    collected = {
      "nixos.role.desktop" = [
        {
          source = "/path/to/audio.nix";
          value = { services.pipewire.enable = true; };
          strategy = "merge";
        }
        {
          source = "/path/to/wayland.nix";
          value = { services.greetd.enable = true; };
          strategy = "merge";
        }
      ];
    };
    sinkDefaults = {
      "nixos.*" = "merge";
      "hm.*" = "merge";
    };
  }
  # => {
  #   nixos.role.desktop = {
  #     __module = { ... merged module ... };
  #     __meta = {
  #       contributors = [ "/path/to/audio.nix" "/path/to/wayland.nix" ];
  #       keys = [ "nixos.role.desktop" ];
  #     };
  #   };
  # }
  ```

  # Arguments

  lib
  : nixpkgs lib for merge operations (required for mkMerge strategy).

  collected
  : Output from collectExports - attrset of sink keys to export records.

  sinkDefaults
  : Optional attrset mapping glob patterns to default strategies.

  enableDebug
  : Include __meta with contributor info (default: true).
*/
{
  lib,
  collected ? { },
  sinkDefaults ? { },
  enableDebug ? true,
}:
let
  # Match a sink key against a pattern (supports * glob at end)
  matchesPattern =
    pattern: key:
    let
      # Convert "nixos.*" to "nixos."
      prefix =
        if lib.hasSuffix ".*" pattern then
          lib.removeSuffix "*" pattern
        else if lib.hasSuffix "*" pattern then
          lib.removeSuffix "*" pattern
        else
          pattern;
      hasGlob = lib.hasSuffix "*" pattern;
    in
    if hasGlob then lib.hasPrefix prefix key else key == pattern;

  # Find default strategy for a sink key
  findDefaultStrategy =
    sinkKey:
    let
      patterns = builtins.attrNames sinkDefaults;
      matching = builtins.filter (p: matchesPattern p sinkKey) patterns;
    in
    # Use first matching pattern, or null if none match
    if matching != [ ] then sinkDefaults.${builtins.head matching} else null;

  # Validate that a strategy is valid
  isValidStrategy =
    s:
    builtins.elem s [
      "merge"
      "override"
      "list-append"
      "mkMerge"
      null
    ];

  # Merge two values with a given strategy
  mergeWithStrategy =
    strategy: existing: new:
    if strategy == "override" || strategy == null then
      # Last writer wins
      new
    else if strategy == "merge" then
      # Deep merge
      if lib.isAttrs existing && lib.isAttrs new then lib.recursiveUpdate existing new else new
    else if strategy == "list-append" then
      # Concatenate lists
      if builtins.isList existing && builtins.isList new then
        existing ++ new
      else if builtins.isList new then
        new
      else if builtins.isList existing then
        existing
      else
        throw "list-append strategy requires list values, got: ${builtins.typeOf new}"
    else if strategy == "mkMerge" then
      # For module fragments, collect them for mkMerge
      # Return a special marker that we'll process later
      # Skip the initial empty accumulator
      if existing == { } then
        {
          __mkMerge = true;
          values = [ new ];
        }
      else
        {
          __mkMerge = true;
          values = (if existing ? __mkMerge then existing.values else [ existing ]) ++ [ new ];
        }
    else
      throw "Unknown merge strategy: ${strategy}";

  # Build a single sink from its export records
  buildSink =
    sinkKey: exportRecords:
    let
      # Sort by source path for deterministic ordering
      sorted = builtins.sort (a: b: a.source < b.source) exportRecords;

      # Determine effective strategy for each export
      withStrategies = map (
        record:
        let
          effectiveStrategy =
            if record.strategy != null then record.strategy else findDefaultStrategy sinkKey;
        in
        record // { effectiveStrategy = effectiveStrategy; }
      ) sorted;

      # Validate strategies
      invalidStrategies = builtins.filter (r: !isValidStrategy r.effectiveStrategy) withStrategies;

      # Check for strategy conflicts (different strategies for same sink)
      strategies = map (r: r.effectiveStrategy) withStrategies;
      uniqueStrategies = lib.unique (builtins.filter (s: s != null) strategies);
      hasConflict = builtins.length uniqueStrategies > 1;

      conflictError =
        let
          strategyInfo = map (
            r: "  - ${r.source} (strategy: ${toString r.effectiveStrategy})"
          ) withStrategies;
        in
        ''
          imp.buildExportSinks: conflicting strategies for sink '${sinkKey}'
          Contributors:
          ${builtins.concatStringsSep "\n" strategyInfo}

          All exports to the same sink must use compatible strategies.
        '';

      # Merge all values using the common strategy
      mergedValue =
        let
          # Use the first non-null strategy, or "override" as default
          strategy = if uniqueStrategies != [ ] then builtins.head uniqueStrategies else "override";
        in
        builtins.foldl' (acc: record: mergeWithStrategy strategy acc record.value) { } withStrategies;

      # Finalize mkMerge if needed
      # For mkMerge with module functions, wrap in a module that imports them
      finalValue =
        if mergedValue ? __mkMerge then
          let
            values = mergedValue.values;
            # Check if values are functions (modules)
            allFunctions = builtins.all builtins.isFunction values;
          in
          if allFunctions then
            # Wrap module functions in a single module that imports them all
            { imports = values; }
          else
            # Non-function values: use lib.mkMerge directly
            lib.mkMerge values
        else
          mergedValue;

      # Build metadata
      meta = {
        contributors = map (r: r.source) sorted;
        strategy = if uniqueStrategies != [ ] then builtins.head uniqueStrategies else "override";
      };

    in
    if invalidStrategies != [ ] then
      throw "imp.buildExportSinks: invalid strategy in ${(builtins.head invalidStrategies).source}"
    else if hasConflict then
      throw conflictError
    else if enableDebug then
      {
        __module = finalValue;
        __meta = meta;
      }
    else
      finalValue;

  # Build all sinks
  sinks =
    let
      sinkKeys = builtins.attrNames collected;
    in
    builtins.foldl' (
      acc: sinkKey:
      let
        # Split "nixos.role.desktop" into ["nixos" "role" "desktop"]
        parts = lib.splitString "." sinkKey;
        value = buildSink sinkKey collected.${sinkKey};
      in
      # Use lib.setAttrByPath to create nested structure
      lib.recursiveUpdate acc (lib.setAttrByPath parts value)
    ) { } sinkKeys;

in
sinks
