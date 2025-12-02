# imp 😈

Recursively import Nix files from directories as NixOS modules or nested attrsets.

## Usage

Add `imp` as a flake input:

```nix
{
  inputs.imp.url = "github:Alb-O/imp";
}
```

### Usage as a Module Importer

Use `imp` as a function to create a NixOS/flake-parts module that imports all `.nix` files from a directory:

```nix
{ inputs, ... }:
{
  imports = [ (inputs.imp ./nix) ];
}
```

With flake-parts:

```nix
{
  inputs.imp.url = "github:Alb-O/imp";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; }
    (inputs.imp ./nix);
}
```

### Usage as a File List Builder

Chain filters and transforms to get a list of files:

```nix
let
  imp = inputs.imp.withLib lib;
in
imp.filter (lib.hasInfix "/services/").leafs ./modules
# Returns: [ ./modules/services/nginx.nix ./modules/services/postgres.nix ... ]
```

### Usage as a Tree Builder

Build nested attrsets from directory structure, e.g. for flake outputs:

```nix
# Directory structure:
#   outputs/
#     apps.nix
#     checks.nix
#     packages/
#       foo.nix
#       bar.nix

imp.treeWith lib import ./outputs
# Returns:
# {
#   apps = <imported from apps.nix>;
#   checks = <imported from checks.nix>;
#   packages = {
#     foo = <imported from foo.nix>;
#     bar = <imported from bar.nix>;
#   };
# }
```

## Naming Conventions

| Path              | Attribute | Notes                                      |
| ----------------- | --------- | ------------------------------------------ |
| `foo.nix`         | `foo`     | Typical file as a module                   |
| `foo/default.nix` | `foo`     | Typical directory module with default.nix  |
| `foo_.nix`        | `foo`     | Trailing `_` escapes reserved names in nix |
| `_foo.nix`        | (ignored) | Leading `_` means hidden (not imported)    |
| `_foo/`           | (ignored) | Hidden directory                           |

## API Reference

### Core

#### `imp <path>`

Import all `.nix` files from a path as a NixOS module.

```nix
{ imports = [ (imp ./modules) ]; }
```

#### `.withLib <lib>`

Required before using `.leafs`, `.files`, `.tree`, or `.treeWith`.

```nix
imp.withLib nixpkgs.lib
```

### Filtering

#### `.filter <predicate>` / `.filterNot <predicate>`

Filter paths by predicate. Multiple filters compose with AND.

```nix
imp.filter (lib.hasInfix "/services/") ./modules
imp.filterNot (lib.hasInfix "/deprecated/") ./modules
```

#### `.match <regex>` / `.matchNot <regex>`

Filter paths by regex (uses `builtins.match`).

```nix
imp.match ".*/[a-z]+@(foo|bar)\.nix" ./nix
```

#### `.initFilter <predicate>`

Replace the default filter. By default, imp finds `.nix` files and excludes paths containing `/_`.

```nix
# Import markdown files instead
imp.initFilter (lib.hasSuffix ".md") ./docs
```

### Transforming

#### `.map <function>`

Transform each matched path.

```nix
imp.map import ./packages
# Returns list of imported values instead of paths
```

#### `.mapTree <function>`

Transform values when using `.tree`. Composes with multiple calls.

```nix
(imp.withLib lib)
  .mapTree (drv: drv // { meta.priority = 5; })
  .tree ./packages
```

### Tree Building

#### `.tree <path>`

Build a nested attrset from directory structure. Requires `.withLib`.

```nix
(imp.withLib lib).tree ./outputs
```

#### `.treeWith <lib> <transform> <path>`

Convenience function combining `.withLib`, `.mapTree`, and `.tree`.

```nix
# These are equivalent:
((imp.withLib lib).mapTree (f: f args)).tree ./outputs
imp.treeWith lib (f: f args) ./outputs
```

Real-world example - loading per-system flake outputs:

```nix
{
  outputs = { self, nixpkgs, imp, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        args = { inherit self pkgs; };
      in
      imp.treeWith nixpkgs.lib (f: f args) ./outputs
    );
}
```

Where each file in `./outputs/` is a function taking `args`:

```nix
# outputs/packages.nix
{ pkgs, ... }: {
  hello = pkgs.hello;
  cowsay = pkgs.cowsay;
}
```

### File Lists

#### `.leafs <path>` / `.files`

Get the list of matched files. Requires `.withLib`.

```nix
(imp.withLib lib).leafs ./modules
# Returns: [ ./modules/foo.nix ./modules/bar.nix ... ]

# Or with pre-configured paths:
imp.withLib lib
  |> (i: i.addPath ./modules)
  |> (i: i.filter (lib.hasInfix "/services/"))
  |> (i: i.files)
```

#### `.pipeTo <function> <path>`

Apply a function to the file list.

```nix
(imp.withLib lib).pipeTo builtins.length ./modules
# Returns: 42
```

### Extending

#### `.addPath <path>`

Add additional paths to search.

```nix
imp
  |> (i: i.addPath ./modules)
  |> (i: i.addPath ./vendor)
  |> (i: i.leafs)
```

#### `.addAPI <attrset>`

Extend imp with custom methods. Methods receive `self` for chaining.

```nix
let
  myImporter = imp.addAPI {
    services = self: self.filter (lib.hasInfix "/services/");
    packages = self: self.filter (lib.hasInfix "/packages/");
  };
in
myImporter.services ./nix
```

#### `.new`

Returns a fresh imp with empty state, preserving custom API.

## Examples

### Organizing NixOS Modules

```
nixos/
  modules/
    services/
      nginx.nix
      postgres.nix
    hardware/
      gpu.nix
    _helpers.nix  # ignored - helper functions
```

```nix
{ imports = [ (imp ./nixos/modules) ]; }
```

### Flake with Per-System Outputs

```
outputs/
  apps.nix
  checks.nix
  devShells.nix
  packages/
    foo.nix
    bar.nix
```

```nix
# flake.nix
{
  outputs = { nixpkgs, imp, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      imp.treeWith nixpkgs.lib (f: f { inherit pkgs; }) ./outputs
    );
}

# outputs/apps.nix
{ pkgs, ... }: {
  hello = { type = "app"; program = "${pkgs.hello}/bin/hello"; };
}

# outputs/packages/foo.nix
{ pkgs, ... }:
pkgs.stdenv.mkDerivation { name = "foo"; /* ... */ }
```

### Conditional Module Loading

```nix
let
  imp = inputs.imp.withLib lib;

  serverModules = imp.filter (lib.hasInfix "/server/") ./modules;
  desktopModules = imp.filter (lib.hasInfix "/desktop/") ./modules;
in
{
  imports = [
    (if isServer then serverModules else desktopModules)
  ];
}
```

## Development

### Tests

```sh
nix run .#tests    # Run unit tests
nix flake check    # Full check including formatting
```

### Formatting

```sh
nix fmt    # Uses treefmt
```

## Attribution

- Originally written by @vic as [import-tree](https://github.com/vic/import-tree).
- `.tree` inspired by [flakelight](https://github.com/nix-community/flakelight)'s autoload feature.

## License

Apache-2.0 - see [LICENSE](LICENSE).
