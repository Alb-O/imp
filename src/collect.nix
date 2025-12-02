/*
  File collection and filtering logic.

  This module handles:
  - Recursive file discovery from paths
  - Filter composition and application
  - Path normalization (absolute to relative)
*/
let
  utils = import ./lib.nix;
  inherit (utils)
    compose
    and
    andNot
    isDirectory
    isPathLike
    hasOutPath
    isimp
    ;
in

/*
  Core evaluation: applies filters/maps and produces the final result.

  When pipef is null, returns a NixOS module.
  Otherwise, applies pipef to the collected file list.
*/
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
result
