# Recursive module importer with filtering and mapping capabilities
#
# Can be used as:
#   - A function: imp ./path -> NixOS module with imports
#   - A builder: imp.filter(...).map(...).leafs ./path -> list of processed files
#   - A tree builder: imp.withLib(lib).tree ./path -> nested attrset
let
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

      # Delays lib access until module evaluation
      module =
        { lib, ... }:
        {
          imports = leafs lib path;
        };

      leafs =
        lib:
        let
          treeFiles = t: (t.withLib lib).files;

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

          nixFilter = andNot (lib.hasInfix "/_") (lib.hasSuffix ".nix");
          initialFilter = if initf != null then initf else nixFilter;
          pathFilter = compose (and filterf initialFilter) toString;
          otherFilter = and filterf (if initf != null then initf else (_: true));
          filter = x: if isPathLike x then pathFilter x else otherFilter x;

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

  compose =
    g: f: x:
    g (f x);

  # Applies f first, then g (reversed for partial application in config building)
  and =
    g: f: x:
    f x && g x;

  andNot = g: and (x: !(g x));

  matchesRegex = re: p: builtins.match re p != null;

  mapAttr =
    attrs: k: f:
    attrs // { ${k} = f attrs.${k}; };

  isDirectory = and (x: builtins.readFileType x == "directory") isPathLike;

  isPathLike = x: builtins.isPath x || builtins.isString x || hasOutPath x;

  hasOutPath = and (x: x ? outPath) builtins.isAttrs;

  isimp = and (x: x ? __config.__functor) builtins.isAttrs;

  inModuleEval = and (x: x ? options) builtins.isAttrs;

  functor = self: arg: perform self.__config (if inModuleEval arg then [ ] else arg);

  callable =
    let
      initial = {
        api = { };
        mapf = (i: i);
        treef = import;
        filterf = _: true;
        paths = [ ];

        # State functor: takes an update function returning new state.
        # Example: `config (c: c // x)` merges x into config.
        __functor =
          config: update:
          let
            updated = update config;
            current = config update;
            boundAPI = builtins.mapAttrs (_: g: g current) updated.api;

            # Helpers for accumulating config attributes
            accAttr = attrName: acc: config (c: mapAttr (update c) attrName acc);
            mergeAttrs = attrs: config (c: (update c) // attrs);
          in
          boundAPI
          // {
            __config = updated;
            __functor = functor;

            # Accumulating modifiers
            filter = filterf: accAttr "filterf" (and filterf);
            filterNot = filterf: accAttr "filterf" (andNot filterf);
            match = regex: accAttr "filterf" (and (matchesRegex regex));
            matchNot = regex: accAttr "filterf" (andNot (matchesRegex regex));
            map = mapf: accAttr "mapf" (compose mapf);
            mapTree = treef: accAttr "treef" (compose treef);
            addPath = path: accAttr "paths" (p: p ++ [ path ]);
            addAPI = api: accAttr "api" (a: a // api);

            # Non-accumulating modifiers
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

            new = callable;
          };
      };
    in
    initial (config: config);

in
callable
