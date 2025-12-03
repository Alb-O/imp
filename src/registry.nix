/**
  Registry: Named module discovery and resolution.

  Scans a directory tree and builds a nested attrset mapping names to paths.
  Files can then reference modules by name instead of relative paths.

  # Example

  Directory structure:

  ```
  nix/
    home/
      alice/default.nix
      bob.nix
    modules/
      nixos/
        base.nix
      home/
        base.nix
  ```

  Produces registry:

  ```nix
  {
    home = {
      __path = <nix/home>;  # directory itself
      alice = <path>;
      bob = <path>;
    };
    modules = {
      __path = <nix/modules>;
      nixos = {
        __path = <nix/modules/nixos>;
        base = <path>;
      };
      home = { ... };
    };
  }
  ```

  Usage in files:

  ```nix
  { registry, ... }:
  {
    # Use the directory path
    imports = [ (imp registry.modules.nixos) ];
    # Or a specific file
    imports = [ registry.modules.home.base ];
  }
  ```

  Note: Directories are "path-like" (have __path) so they work with `imp`.
*/
{
  lib,
  filterf ? _: true,
}:
let
  /**
    Build registry from a directory.
    Returns nested attrset where each directory has __path and child entries.

    # Arguments

    root
    : Root directory path to scan.
  */
  buildRegistry =
    root:
    let
      entries = builtins.readDir root;

      toAttrName =
        name:
        let
          withoutNix = lib.removeSuffix ".nix" name;
        in
        lib.removeSuffix "_" withoutNix;

      shouldInclude = name: !(lib.hasPrefix "_" name) && filterf (toString root + "/" + name);

      processEntry =
        name: type:
        let
          path = root + "/${name}";
          attrName = toAttrName name;
        in
        if type == "regular" && lib.hasSuffix ".nix" name then
          { ${attrName} = path; }
        else if type == "directory" then
          let
            hasDefault = builtins.pathExists (path + "/default.nix");
          in
          if hasDefault then
            # Directory with default.nix is a single module
            { ${attrName} = path; }
          else
            # Directory without default.nix: include __path + recurse into children
            {
              ${attrName} = {
                __path = path;
              }
              // buildRegistry path;
            }
        else
          { };

      filteredEntries = lib.filterAttrs (name: _: shouldInclude name) entries;
      processed = lib.mapAttrsToList processEntry filteredEntries;
    in
    lib.foldl' (acc: x: acc // x) { } processed;

  /**
    Check if a value is a registry node (has __path).

    # Arguments

    x
    : Value to check.
  */
  isRegistryNode = x: lib.isAttrs x && x ? __path;

  /**
    Get the path from a registry value.
    Works for both direct paths and registry nodes with __path.

    # Arguments

    x
    : Registry value (path or node with __path).
  */
  toPath = x: if isRegistryNode x then x.__path else x;

  /**
    Flatten registry to dot-notation paths.

    # Example

    ```nix
    flattenRegistry registry
    # => { home.alice = <path>; modules.nixos = <path>; modules.nixos.base = <path>; }
    ```

    # Arguments

    registry
    : Registry attrset to flatten.
  */
  flattenRegistry =
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
            # Include the directory itself at the parent key
            if prefix == "" then acc else acc // { ${prefix} = value; }
          else if isRegistryNode value then
            # Registry node: include both the node path and recurse
            acc // { ${key} = value.__path; } // flatten key value
          else if lib.isAttrs value && !(lib.isDerivation value) && !(value ? outPath) then
            acc // flatten key value
          else
            acc // { ${key} = value; }
        ) { } attrs;
    in
    flatten "" registry;

  /**
    Lookup a dotted path in the registry.

    # Example

    ```nix
    lookup "home.alice" registry
    # => <path>
    ```

    # Arguments

    path
    : Dot-separated path string (e.g. "home.alice").

    registry
    : Registry attrset to search.
  */
  lookup =
    path: registry:
    let
      parts = lib.splitString "." path;
      result = lib.getAttrFromPath parts registry;
    in
    toPath result;

  /**
    Create a resolver function that looks up names in the registry.
    Returns a function: name -> path

    # Example

    ```nix
    resolve = makeResolver registry;
    resolve "home.alice"
    # => <path>
    ```

    # Arguments

    registry
    : Registry attrset to create resolver for.
  */
  makeResolver =
    registry:
    let
      flat = flattenRegistry registry;
    in
    name:
    flat.${name}
      or (throw "imp registry: module '${name}' not found. Available: ${toString (builtins.attrNames flat)}");

in
{
  inherit
    buildRegistry
    flattenRegistry
    lookup
    makeResolver
    toPath
    isRegistryNode
    ;
}
