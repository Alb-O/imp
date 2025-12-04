/**
  API method definitions for imp.

  This module defines all chainable methods available on the imp object.
  Methods are organized into categories:

  - Filtering: filter, filterNot, match, matchNot, initFilter
  - Transforming: map, mapTree
  - Tree building: tree, treeWith, configTree, configTreeWith
  - File lists: leafs, files, pipeTo
  - Extending: addPath, addAPI, withLib, new
*/
let
  utils = import ./lib.nix;
  inherit (utils)
    compose
    and
    andNot
    matchesRegex
    mapAttr
    ;
in

{
  config,
  update,
  updated,
  current,
  callable,
}:
let
  # Accumulates values into a config attribute
  accAttr = attrName: acc: config (c: mapAttr (update c) attrName acc);

  # Merges attributes into config
  mergeAttrs = attrs: config (c: (update c) // attrs);
in
{
  /**
    Filter paths by predicate. Multiple filters compose with AND.

    # Example

    ```nix
    imp.filter (lib.hasInfix "/services/") ./modules
    imp.filterNot (lib.hasInfix "/deprecated/") ./modules
    ```

    # Arguments

    predicate
    : Function that receives a path string and returns boolean.
  */
  filter = predicate: accAttr "filterf" (and predicate);

  /**
    Exclude paths matching predicate. Opposite of filter.

    # Example

    ```nix
    imp.filterNot (lib.hasInfix "/deprecated/") ./modules
    ```

    # Arguments

    predicate
    : Function that receives a path string and returns boolean.
  */
  filterNot = predicate: accAttr "filterf" (andNot predicate);

  /**
    Filter paths by regex. Uses builtins.match.

    # Example

    ```nix
    imp.match ".*[/]services[/].*" ./nix
    ```

    # Arguments

    regex
    : Regular expression string.
  */
  match = regex: accAttr "filterf" (and (matchesRegex regex));

  /**
    Exclude paths matching regex. Opposite of match.

    # Example

    ```nix
    imp.matchNot ".*[/]test[/].*" ./src
    ```

    # Arguments

    regex
    : Regular expression string.
  */
  matchNot = regex: accAttr "filterf" (andNot (matchesRegex regex));

  /**
    Replace the default filter. By default, imp finds .nix files
    and excludes paths containing underscore prefixes.

    # Example

    ```nix
    # Import markdown files instead of nix files
    imp.initFilter (lib.hasSuffix ".md") ./docs
    ```

    # Arguments

    predicate
    : Function that receives a path string and returns boolean.
  */
  initFilter = predicate: mergeAttrs { initf = predicate; };

  /**
    Transform each matched path. Composes with multiple calls.

    # Example

    ```nix
    imp.map import ./packages
    ```

    # Arguments

    f
    : Transformation function applied to each path or value.
  */
  map = f: accAttr "mapf" (compose f);

  /**
    Transform values when building a tree with .tree. Composes with multiple calls.

    # Example

    ```nix
    (imp.withLib lib)
      .mapTree (drv: drv // { meta.priority = 5; })
      .tree ./packages
    ```

    # Arguments

    f
    : Transformation function applied to each tree value.
  */
  mapTree = f: accAttr "treef" (compose f);

  /**
    Provide nixpkgs lib. Required before using .leafs, .files, .tree, or .configTree.

    # Example

    ```nix
    imp.withLib pkgs.lib
    imp.withLib inputs.nixpkgs.lib
    ```

    # Arguments

    lib
    : The nixpkgs lib attribute set.
  */
  withLib = lib: mergeAttrs { inherit lib; };

  /**
    Add additional paths to search.

    # Example

    ```nix
    (imp.withLib lib)
      .addPath ./modules
      .addPath ./vendor
      .leafs
    ```

    # Arguments

    path
    : Path to add to the search.
  */
  addPath = path: accAttr "paths" (p: p ++ [ path ]);

  /**
    Extend imp with custom methods. Methods receive self for chaining.

    # Example

    ```nix
    let
      myImp = imp.addAPI {
        services = self: self.filter (lib.hasInfix "/services/");
        packages = self: self.filter (lib.hasInfix "/packages/");
      };
    in
    myImp.services ./nix
    ```

    # Arguments

    api
    : Attribute set of name = self: ... methods.
  */
  addAPI = api: accAttr "api" (a: a // api);

  /**
    Apply a function to the final file list.

    # Example

    ```nix
    (imp.withLib lib).pipeTo builtins.length ./modules
    ```

    # Arguments

    f
    : Function to apply to the file list.
  */
  pipeTo = f: mergeAttrs { pipef = f; };

  /**
    Get the list of matched files. Requires .withLib.

    # Example

    ```nix
    (imp.withLib lib).leafs ./modules
    ```
  */
  leafs = mergeAttrs { pipef = (i: i); };

  # Terminal operations (not documented - internal)
  result = current [ ];
  files = current.leafs.result;

  /**
    Build a nested attrset from directory structure. Requires .withLib.

    Directory names become attribute names. Files are imported and their
    values placed at the corresponding path.

    # Example

    ```nix
    (imp.withLib lib).tree ./outputs
    # { packages.hello = <imported>; apps.run = <imported>; }
    ```

    # Arguments

    path
    : Root directory to build tree from.
  */
  tree =
    path:
    if updated.lib == null then
      throw "You need to call withLib before using tree."
    else
      import ./tree.nix {
        inherit (updated) lib treef filterf;
      } path;

  /**
    Convenience function combining .withLib, .mapTree, and .tree.

    # Example

    ```nix
    # These are equivalent:
    ((imp.withLib lib).mapTree (f: f args)).tree ./outputs
    imp.treeWith lib (f: f args) ./outputs
    ```

    # Arguments

    lib
    : The nixpkgs lib attribute set.

    f
    : Transformation function for tree values.

    path
    : Root directory to build tree from.
  */
  treeWith =
    lib: f: path:
    ((current.withLib lib).mapTree f).tree path;

  /**
    Build a module where directory structure maps to NixOS option paths.
    Each file receives module args and returns config values.

    # Example

    ```nix
    { inputs, lib, ... }: {
      imports = [ ((inputs.imp.withLib lib).configTree ./config) ];
    }
    # File ./config/programs/git.nix sets config.programs.git
    ```

    # Arguments

    path
    : Root directory containing config files.
  */
  configTree =
    path:
    if updated.lib == null then
      throw "You need to call withLib before using configTree."
    else
      import ./configTree.nix {
        inherit (updated) lib filterf;
      } path;

  /**
    Like .configTree but passes extra arguments to each file.

    # Example

    ```nix
    (imp.withLib lib).configTreeWith { myArg = "value"; } ./config
    ```

    # Arguments

    extraArgs
    : Additional arguments passed to each config file.

    path
    : Root directory containing config files.
  */
  configTreeWith =
    extraArgs: path:
    if updated.lib == null then
      throw "You need to call withLib before using configTreeWith."
    else
      import ./configTree.nix {
        inherit (updated) lib filterf;
        inherit extraArgs;
      } path;

  /**
    Merge multiple config trees into a single module.

    # Example

    ```nix
    # Later trees override earlier (default)
    (imp.withLib lib).mergeConfigTrees [ ./base ./overrides ]

    # With mkMerge semantics
    (imp.withLib lib).mergeConfigTrees { strategy = "merge"; } [ ./base ./local ]
    ```

    # Arguments

    options (optional)
    : Attribute set with strategy ("override" or "merge") and extraArgs.

    paths
    : List of directories to merge.
  */
  mergeConfigTrees =
    arg:
    if updated.lib == null then
      throw "You need to call withLib before using mergeConfigTrees."
    else if builtins.isList arg then
      # Called as: mergeConfigTrees [ paths ]
      import ./mergeConfigTrees.nix {
        inherit (updated) lib filterf;
      } arg
    else
      # Called as: mergeConfigTrees { options } [ paths ]
      paths:
      import ./mergeConfigTrees.nix {
        inherit (updated) lib filterf;
        strategy = arg.strategy or "override";
        extraArgs = arg.extraArgs or { };
      } paths;

  /**
    Returns a fresh imp instance with empty state, preserving custom API extensions.

    # Example

    ```nix
    let
      customImp = imp.addAPI { myMethod = self: self.filter predicate; };
      fresh = customImp.new;
    in
    fresh.myMethod ./src
    ```
  */
  new = callable;

  /**
    Build a modules list from mixed items. Handles paths, registry nodes, and modules.

    # Example

    ```nix
    modules = imp.imports [
      registry.hosts.server
      registry.modules.nixos.base
      ./local-module.nix
      inputs.home-manager.nixosModules.home-manager
      { services.openssh.enable = true; }
    ];
    ```

    # Arguments

    items
    : List of paths, registry nodes, or module values.
  */
  imports =
    items:
    let
      registryLib = import ./registry.nix { lib = updated.lib or builtins; };
      isPath = p: builtins.isPath p || (builtins.isString p && builtins.substring 0 1 p == "/");
      process =
        item:
        if registryLib.isRegistryNode item then
          import item.__path
        else if isPath item then
          import item
        else
          item;
    in
    builtins.map process items;

  /**
    Namespace for dependency analysis and visualization.

    # Example

    ```nix
    graph = (imp.withLib lib).analyze.registry { registry = myRegistry; }
    html = (imp.withLib lib).analyze.toHtml graph
    json = (imp.withLib lib).analyze.toJson graph
    ```
  */
  analyze =
    if updated.lib == null then
      throw "You need to call withLib before using analyze."
    else
      let
        analyzeLib = import ./analyze.nix { inherit (updated) lib; };
        visualizeLib = import ./visualize { inherit (updated) lib; };
      in
      analyzeLib // visualizeLib;
}
