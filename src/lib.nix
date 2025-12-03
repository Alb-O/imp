# Internal utility functions for imp.
rec {
  # Function composition: (compose g f) x = g(f(x))
  compose =
    g: f: x:
    g (f x);

  # Predicate combinators
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
  hasOutPath = and (x: x ? outPath) builtins.isAttrs;

  # Registry nodes have __path attribute
  isRegistryNode = and (x: x ? __path) builtins.isAttrs;

  # Extract path from registry node or return as-is
  toPath = x: if isRegistryNode x then x.__path else x;

  isPathLike = x: builtins.isPath x || builtins.isString x || hasOutPath x || isRegistryNode x;

  isDirectory = and (x: builtins.readFileType (toPath x) == "directory") isPathLike;

  isimp = and (x: x ? __config.__functor) builtins.isAttrs;

  inModuleEval = and (x: x ? options) builtins.isAttrs;
}
