/*
  Builds nested attrset from directory structure.

  Naming:  foo.nix | foo/default.nix -> { foo = ... }
           foo_.nix                  -> { foo = ... }  (escapes reserved names)
           _foo.nix | _foo/          -> ignored

  Example:

    Directory structure:
      outputs/
        apps.nix
        checks.nix
        packages/
          foo.nix
          bar.nix

    imp.treeWith lib import ./outputs

    Returns:
      {
        apps = <imported from apps.nix>;
        checks = <imported from checks.nix>;
        packages = {
          foo = <imported from foo.nix>;
          bar = <imported from bar.nix>;
        };
      }

  Usage:

    (imp.withLib lib).tree ./outputs

  Or with transform:

    ((imp.withLib lib).mapTree (f: f args)).tree ./outputs
    imp.treeWith lib (f: f args) ./outputs
*/
{
  lib,
  treef ? import,
  filterf,
}:
let
  buildTree =
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
          { ${attrName} = treef path; }
        else if type == "directory" then
          let
            hasDefault = builtins.pathExists (path + "/default.nix");
          in
          if hasDefault then { ${attrName} = treef path; } else { ${attrName} = buildTree path; }
        else
          { };

      filteredEntries = lib.filterAttrs (name: _: shouldInclude name) entries;
      processed = lib.mapAttrsToList processEntry filteredEntries;
    in
    lib.foldl' (acc: x: acc // x) { } processed;
in
buildTree
