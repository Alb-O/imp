/*
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

/*
  Builds the API methods for a given state.

  Arguments:
  - config: the state functor
  - update: the current update function
  - updated: the updated config state
  - current: the current imp instance
  - callable: reference to create fresh instances
*/
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
  /*
    .filter <predicate> / .filterNot <predicate>
    Filter paths by predicate. Multiple filters compose with AND.

      imp.filter (lib.hasInfix "/services/") ./modules
      imp.filterNot (lib.hasInfix "/deprecated/") ./modules
  */
  filter = filterf: accAttr "filterf" (and filterf);
  filterNot = filterf: accAttr "filterf" (andNot filterf);

  /*
    .match <regex> / .matchNot <regex>
    Filter paths by regex (uses builtins.match).

      imp.match ".+services.+" ./nix
  */
  match = regex: accAttr "filterf" (and (matchesRegex regex));
  matchNot = regex: accAttr "filterf" (andNot (matchesRegex regex));

  /*
    .initFilter <predicate>
    Replace the default filter. By default, imp finds .nix files
    and excludes paths containing /_.

      # Import markdown files instead
      imp.initFilter (lib.hasSuffix ".md") ./docs
  */
  initFilter = initf: mergeAttrs { inherit initf; };

  /*
    .map <function>
    Transform each matched path.

      imp.map import ./packages
      # Returns list of imported values instead of paths
  */
  map = mapf: accAttr "mapf" (compose mapf);

  /*
    .mapTree <function>
    Transform values when using `.tree`. Composes with multiple calls.

      (imp.withLib lib)
        .mapTree (drv: drv // { meta.priority = 5; })
        .tree ./packages
  */
  mapTree = treef: accAttr "treef" (compose treef);

  /*
    .withLib <lib>
    Required before using .leafs, .files, .tree, or .treeWith.

      imp.withLib nixpkgs.lib
  */
  withLib = lib: mergeAttrs { inherit lib; };

  /*
    .addPath <path>
    Add additional paths to search.

      imp
        |> (i: i.addPath ./modules)
        |> (i: i.addPath ./vendor)
        |> (i: i.leafs)
  */
  addPath = path: accAttr "paths" (p: p ++ [ path ]);

  /*
    .addAPI <attrset>
    Extend `imp` with custom methods. Methods receive `self` for chaining.

      let
        myImporter = imp.addAPI {
          services = self: self.filter (lib.hasInfix "/services/");
          packages = self: self.filter (lib.hasInfix "/packages/");
        };
      in
      myImporter.services ./nix
  */
  addAPI = api: accAttr "api" (a: a // api);

  /*
    .pipeTo <function>
    Apply a function to the file list.

      (imp.withLib lib).pipeTo builtins.length ./modules
      # Returns: 42
  */
  pipeTo = pipef: mergeAttrs { inherit pipef; };

  /*
    .leafs <path> / .files
    Get the list of matched files. Requires .withLib.

      (imp.withLib lib).leafs ./modules
      # Returns: [ ./modules/foo.nix ./modules/bar.nix ... ]
  */
  leafs = mergeAttrs { pipef = (i: i); };

  # Terminal operations
  result = current [ ];
  files = current.leafs.result;

  /*
    .tree <path>
    Build a nested attrset from directory structure. Requires .withLib.

      (imp.withLib lib).tree ./outputs
  */
  tree =
    path:
    if updated.lib == null then
      throw "You need to call withLib before using tree."
    else
      import ./tree.nix {
        inherit (updated) lib treef filterf;
      } path;

  /*
    .treeWith <lib> <transform> <path>
    Convenience function combining .withLib, .mapTree, and .tree.

      # These are equivalent:
      ((imp.withLib lib).mapTree (f: f args)).tree ./outputs
      imp.treeWith lib (f: f args) ./outputs
  */
  treeWith =
    lib: f: path:
    ((current.withLib lib).mapTree f).tree path;

  /*
    .configTree <path>
    Build a module where directory structure maps to option paths.
    Each file receives module args and returns config values.

      { inputs, ... }:
      {
        imports = [ ((inputs.imp.withLib lib).configTree ./home) ];
      }
  */
  configTree =
    path:
    if updated.lib == null then
      throw "You need to call withLib before using configTree."
    else
      import ./configTree.nix {
        inherit (updated) lib filterf;
      } path;

  /*
    .configTreeWith <extraArgs> <path>
    Like .configTree but passes extra arguments to each file.

      ((inputs.imp.withLib lib).configTreeWith { myArg = "value"; } ./home)
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

  /*
    .mergeConfigTrees [<options>] <paths>
    Merge multiple config trees into a single module.

    Can be called two ways:
      imp.mergeConfigTrees [ path1 path2 ]           # uses defaults
      imp.mergeConfigTrees { strategy = "merge"; } [ path1 path2 ]

    Options:
      - strategy: "override" (default) or "merge"
        - "override": later trees completely override earlier (recursiveUpdate)
        - "merge": use mkMerge for module system semantics (lists concat, etc.)
      - extraArgs: additional arguments passed to each config file

    Examples:

      # Default: later overrides earlier
      imp.mergeConfigTrees [ ../shell ./. ]

      # With mkMerge: lists concatenate, attrs merge
      imp.mergeConfigTrees { strategy = "merge"; } [ ../shell ./. ]

      # With extra args
      imp.mergeConfigTrees { extraArgs = { foo = "bar"; }; } [ ../shell ./. ]
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

  /*
    .new
    Returns a fresh imp with empty state, preserving custom API.
  */
  new = callable;

  /*
    .analyze
    Namespace for dependency analysis and visualization functions.

    Analyze a registry to discover module relationships:

      graph = imp.analyze.registry { registry = myRegistry; }

    Format the graph as DOT (Graphviz):

      dotString = imp.analyze.toDot graph

    Format as ASCII tree:

      asciiString = imp.analyze.toAsciiTree graph

    Get as JSON-serializable data:

      jsonData = imp.analyze.toJson graph
  */
  analyze =
    if updated.lib == null then
      throw "You need to call withLib before using analyze."
    else
      import ./analyze.nix { inherit (updated) lib; };
}
