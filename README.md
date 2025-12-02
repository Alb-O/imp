# imp

A Nix library to recursively import Nix files from directories as NixOS modules or nested attrsets.

## Installation

Add `imp` as a flake input:

```nix
{
  inputs.imp.url = "github:Alb-O/imp";
}
```

## Quick Start

### As a Module Importer

```nix
{ inputs, ... }:
{
  imports = [ (inputs.imp ./nix) ];
}
```

### With flake-parts

```nix
{
  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; }
    (inputs.imp ./nix);
}
```

### As a Tree Builder

```nix
# outputs/
#   apps.nix
#   packages/
#     foo.nix

imp.treeWith lib import ./outputs
# { apps = <...>; packages = { foo = <...>; }; }
```

## Naming Conventions

| Path              | Attribute | Notes                               |
| ----------------- | --------- | ----------------------------------- |
| `foo.nix`         | `foo`     | File as module                      |
| `foo/default.nix` | `foo`     | Directory module                    |
| `foo_.nix`        | `foo`     | Trailing `_` escapes reserved names |
| `_foo.nix`        | (ignored) | Leading `_` = hidden                |

## API

Full API documentation with examples is inline in the source:

| File                                           | Purpose                                         |
| ---------------------------------------------- | ----------------------------------------------- |
| [`src/api.nix`](src/api.nix)                   | All chainable methods (filter, map, tree, etc.) |
| [`src/collect.nix`](src/collect.nix)           | File collection & filtering logic               |
| [`src/tree.nix`](src/tree.nix)                 | Tree building from directories                  |
| [`src/configTree.nix`](src/configTree.nix)     | NixOS/Home Manager config modules               |
| [`src/flakeOutputs.nix`](src/flakeOutputs.nix) | Flake outputs with per-system detection         |
| [`src/lib.nix`](src/lib.nix)                   | Internal utilities                              |

### Overview

| Method                        | Description                                     |
| ----------------------------- | ----------------------------------------------- |
| `imp <path>`                  | Import directory as NixOS module                |
| `.withLib <lib>`              | Bind nixpkgs lib (required for most operations) |
| `.filter <pred>`              | Filter paths by predicate                       |
| `.match <regex>`              | Filter paths by regex                           |
| `.map <fn>`                   | Transform matched paths                         |
| `.tree <path>`                | Build nested attrset from directory             |
| `.treeWith <lib> <fn> <path>` | Tree with transform                             |
| `.configTree <path>`          | Directory structure → option paths              |
| `.flakeOutputs {...} <path>`  | Auto per-system detection                       |
| `.leafs <path>`               | Get list of matched files                       |
| `.addAPI <attrset>`           | Extend with custom methods                      |

## Examples

### Flake with Per-System Outputs

```nix
{
  outputs = { nixpkgs, imp, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      imp.treeWith nixpkgs.lib
        (f: f { pkgs = nixpkgs.legacyPackages.${system}; })
        ./outputs
    );
}
```

### Config Tree (Home Manager / NixOS)

Directory structure becomes option paths:

```
home/
  programs/
    git.nix      -> programs.git = { ... }
    zsh.nix      -> programs.zsh = { ... }
```

```nix
{ inputs, ... }:
{
  imports = [ ((inputs.imp.withLib lib).configTree ./home) ];
}
```

### Conditional Loading

```nix
let
  imp = inputs.imp.withLib lib;
in
{
  imports = [
    (if isServer
      then imp.filter (lib.hasInfix "/server/") ./modules
      else imp.filter (lib.hasInfix "/desktop/") ./modules)
  ];
}
```

## Development

```sh
nix run .#tests    # Run unit tests
nix flake check    # Full check
nix fmt            # Format with treefmt
```

## Attribution

- Originally written by @vic as [import-tree](https://github.com/vic/import-tree)
- `.tree` inspired by [flakelight](https://github.com/nix-community/flakelight)

## License

Apache-2.0 - see [LICENSE](LICENSE).
