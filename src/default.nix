# Recursive module importer with filtering, mapping, and tree-building capabilities.
#
# Usage modes:
#   imp ./path              -> NixOS module with imports
#   imp.withLib(lib).leafs  -> list of matched files
#   imp.withLib(lib).tree   -> nested attrset from directory structure
#   imp.flakeOutputs {...}  -> flake outputs with auto per-system detection
let
  # Core evaluation: applies filters/maps and produces the final result
  perform =
    {
      lib ? null,
      pipef ? null,
      initf ? null,
      filterf,
      mapf,
      paths,
      ...
    }:
    path:
    let
      result =
        if pipef == null then
          { imports = [ module ]; }
        else if lib == null then
          throw "You need to call withLib before trying to read the tree."
        else
          pipef (leafs lib path);

      # Wraps file list in a module that delays lib access until NixOS evaluation
      module =
        { lib, ... }:
        {
          imports = leafs lib path;
        };

      # Recursively collects and filters files from paths
      leafs =
        lib:
        let
          # Extract files from an imp object
          treeFiles = t: (t.withLib lib).files;

          # Normalize various path-like inputs to file lists
          listFilesRecursive =
            x:
            if isimp x then
              treeFiles x
            else if hasOutPath x then
              listFilesRecursive x.outPath
            else if isDirectory x then
              lib.filesystem.listFilesRecursive x
            else
              [ x ];

          # Default: .nix files, excluding paths with /_
          nixFilter = andNot (lib.hasInfix "/_") (lib.hasSuffix ".nix");
          initialFilter = if initf != null then initf else nixFilter;

          # Compose user filters with initial filter
          pathFilter = compose (and filterf initialFilter) toString;
          otherFilter = and filterf (if initf != null then initf else (_: true));
          filter = x: if isPathLike x then pathFilter x else otherFilter x;

          # Convert absolute paths to relative for consistent filtering across roots
          isFileRelative =
            root:
            { file, rel }:
            if file != null && lib.hasPrefix root file then
              {
                file = null;
                rel = lib.removePrefix root file;
              }
            else
              { inherit file rel; };

          getFileRelative = { file, rel }: if rel == null then file else rel;

          makeRelative =
            roots:
            lib.pipe roots [
              (lib.lists.flatten)
              (builtins.filter isDirectory)
              (builtins.map builtins.toString)
              (builtins.map isFileRelative)
              (fx: fx ++ [ getFileRelative ])
              (
                fx: file:
                lib.pipe {
                  file = builtins.toString file;
                  rel = null;
                } fx
              )
            ];

          rootRelative =
            roots:
            let
              mkRel = makeRelative roots;
            in
            x: if isPathLike x then mkRel x else x;
        in
        root:
        lib.pipe
          [ paths root ]
          [
            (lib.lists.flatten)
            (map listFilesRecursive)
            (lib.lists.flatten)
            (builtins.filter (
              compose filter (rootRelative [
                paths
                root
              ])
            ))
            (map mapf)
          ];

    in
    result;

  # Function composition: (compose g f) x = g(f(x))
  compose =
    g: f: x:
    g (f x);

  # Predicate conjunction with reversed application order for partial application
  and =
    g: f: x:
    f x && g x;

  andNot = g: and (x: !(g x));

  matchesRegex = re: p: builtins.match re p != null;

  # Update a single attribute with a function
  mapAttr =
    attrs: k: f:
    attrs // { ${k} = f attrs.${k}; };

  # Type predicates
  isDirectory = and (x: builtins.readFileType x == "directory") isPathLike;
  isPathLike = x: builtins.isPath x || builtins.isString x || hasOutPath x;
  hasOutPath = and (x: x ? outPath) builtins.isAttrs;
  isimp = and (x: x ? __config.__functor) builtins.isAttrs;
  inModuleEval = and (x: x ? options) builtins.isAttrs;

  # Makes imp callable: imp ./path or imp { config, ... }
  functor = self: arg: perform self.__config (if inModuleEval arg then [ ] else arg);

  # The imp builder object - a stateful configuration that produces the API
  callable =
    let
      # Initial configuration state
      initial = {
        api = { };
        mapf = (i: i);
        treef = import;
        filterf = _: true;
        paths = [ ];

        # State functor: receives update function, returns new state with bound API
        __functor =
          config: update:
          let
            updated = update config;
            current = config update;
            boundAPI = builtins.mapAttrs (_: g: g current) updated.api;

            # Accumulates values into a config attribute
            accAttr = attrName: acc: config (c: mapAttr (update c) attrName acc);
            # Merges attributes into config
            mergeAttrs = attrs: config (c: (update c) // attrs);
          in
          boundAPI
          // {
            __config = updated;
            __functor = functor;

            # Accumulating modifiers (compose with existing values)
            filter = filterf: accAttr "filterf" (and filterf);
            filterNot = filterf: accAttr "filterf" (andNot filterf);
            match = regex: accAttr "filterf" (and (matchesRegex regex));
            matchNot = regex: accAttr "filterf" (andNot (matchesRegex regex));
            map = mapf: accAttr "mapf" (compose mapf);
            mapTree = treef: accAttr "treef" (compose treef);
            addPath = path: accAttr "paths" (p: p ++ [ path ]);
            addAPI = api: accAttr "api" (a: a // api);

            # Non-accumulating modifiers (replace values)
            withLib = lib: mergeAttrs { inherit lib; };
            initFilter = initf: mergeAttrs { inherit initf; };
            pipeTo = pipef: mergeAttrs { inherit pipef; };
            leafs = mergeAttrs { pipef = (i: i); };

            # Terminal operations
            result = current [ ];
            files = current.leafs.result;

            tree =
              path:
              if updated.lib == null then
                throw "You need to call withLib before using tree."
              else
                import ./tree.nix {
                  inherit (updated) lib treef filterf;
                } path;

            treeWith =
              lib: f: path:
              ((current.withLib lib).mapTree f).tree path;

            # Builds flake outputs with automatic per-system detection based on
            # whether each file's function accepts `pkgs` or `system` arguments
            flakeOutputs =
              {
                systems,
                pkgsFor,
                args ? { },
              }:
              path:
              if updated.lib == null then
                throw "You need to call withLib before using flakeOutputs."
              else
                import ./flakeOutputs.nix {
                  inherit (updated) lib treef filterf;
                  inherit systems pkgsFor args;
                } path;

            # Builds a NixOS module where directory structure maps to option paths
            configTree =
              path:
              if updated.lib == null then
                throw "You need to call withLib before using configTree."
              else
                import ./configTree.nix {
                  inherit (updated) lib filterf;
                } path;

            configTreeWith =
              extraArgs: path:
              if updated.lib == null then
                throw "You need to call withLib before using configTreeWith."
              else
                import ./configTree.nix {
                  inherit (updated) lib filterf;
                  inherit extraArgs;
                } path;

            new = callable;
          };
      };
    in
    initial (config: config);

in
callable
