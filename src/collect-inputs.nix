# Collects __inputs declarations from a directory tree.
# Standalone implementation - no nixpkgs dependency, only builtins.
#
# Usage:
#   collectInputs ./nix/outputs
#   # Returns: { treefmt-nix = { url = "..."; }; home-manager = { ... }; }

let
  # Check if path should be excluded (starts with _ in basename)
  isExcluded =
    path:
    let
      str = toString path;
      parts = builtins.filter (x: x != "") (builtins.split "/" str);
      basename = builtins.elemAt parts (builtins.length parts - 1);
    in
    builtins.substring 0 1 basename == "_";

  # Check if a value is an attrset
  isAttrs = builtins.isAttrs;

  # Check if value has __inputs attribute
  hasInputs = x: isAttrs x && x ? __inputs && isAttrs x.__inputs;

  # Extract __inputs from a value (imported file content)
  extractInputs = value: if hasInputs value then value.__inputs else { };

  # Safely import a .nix file and extract __inputs
  importAndExtract =
    path:
    let
      value = import path;
    in
    extractInputs value;

  # Compare two input definitions for equality
  inputsEqual =
    a: b:
    let
      aKeys = builtins.attrNames a;
      bKeys = builtins.attrNames b;
    in
    aKeys == bKeys && builtins.all (k: a.${k} == b.${k}) aKeys;

  # Merge two input attrsets, detecting conflicts
  # Returns: { inputs = <merged>; conflicts = [ { name; sources; } ]; }
  mergeInputs =
    sourcePath: existing: new:
    let
      newNames = builtins.attrNames new;
    in
    builtins.foldl' (
      acc: name:
      if acc.inputs ? ${name} then
        # Check if it's the same definition
        if inputsEqual acc.inputs.${name}.def new.${name} then
          acc # Same definition, keep existing
        else
          # Conflict!
          acc
          // {
            conflicts = acc.conflicts ++ [
              {
                inherit name;
                sources = acc.inputs.${name}.sources ++ [ sourcePath ];
                definitions = [
                  acc.inputs.${name}.def
                  new.${name}
                ];
              }
            ];
          }
      else
        # New input
        acc
        // {
          inputs = acc.inputs // {
            ${name} = {
              def = new.${name};
              sources = [ sourcePath ];
            };
          };
        }
    ) existing newNames;

  # Process a single .nix file
  processFile =
    acc: path:
    let
      inputs = importAndExtract path;
    in
    if inputs == { } then acc else mergeInputs path acc inputs;

  # Recursively process a directory
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
        in
        if isExcluded entryPath then
          acc
        else if entryType == "regular" && builtins.match ".*\\.nix" name != null then
          processFile acc entryPath
        else if entryType == "directory" then
          # Check for default.nix
          let
            defaultPath = entryPath + "/default.nix";
            hasDefault = builtins.pathExists defaultPath;
          in
          if hasDefault then
            # Treat directory with default.nix as a single module
            processFile acc defaultPath
          else
            # Recurse into directory
            processDir acc entryPath
        else
          acc;
    in
    builtins.foldl' process acc names;

  # Main collection function
  collectInputs =
    path:
    let
      pathType = builtins.readFileType path;
      initial = {
        inputs = { };
        conflicts = [ ];
      };

      result =
        if pathType == "regular" then
          processFile initial path
        else if pathType == "directory" then
          processDir initial path
        else
          initial;

      # Format conflict error message
      formatConflict =
        c:
        let
          sourcesStr = builtins.concatStringsSep "\n  - " (map toString c.sources);
          defsStr = builtins.concatStringsSep "\n    " (
            map (d: if d ? url then d.url else builtins.toJSON d) c.definitions
          );
        in
        "input '${c.name}':\n  Sources:\n  - ${sourcesStr}\n  Definitions:\n    ${defsStr}";

      conflictMessages = map formatConflict result.conflicts;
      errorMsg = "imp.collectInputs: conflicting definitions for:\n\n${builtins.concatStringsSep "\n\n" conflictMessages}";

      # Extract just the definitions from the result
      finalInputs = builtins.mapAttrs (_: v: v.def) result.inputs;
    in
    if result.conflicts != [ ] then throw errorMsg else finalInputs;

in
collectInputs
