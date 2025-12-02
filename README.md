# imp

A Nix library to recursively import Nix files from directories as NixOS modules or nested attrsets.

## Installation

Add `imp` as a flake input:

```nix
{
  inputs.imp.url = "github:Alb-O/imp";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";
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

`imp` provides a flake-parts module that auto-loads outputs from a directory:

```nix
{
  outputs = inputs@{ flake-parts, imp, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ imp.flakeModules.default ];

      systems = [ "x86_64-linux" "aarch64-linux" ];

      imp = {
        src = ./outputs;            # Directory to load
        args = { inherit inputs; }; # Extra args for all files
      };
    };
}
```

Directory structure:

```
outputs/
  perSystem/
    packages.nix      -> perSystem.packages (receives pkgs, system, etc.)
    devShells.nix     -> perSystem.devShells
  nixosConfigurations/
    server.nix        -> flake.nixosConfigurations.server
  overlays.nix        -> flake.overlays
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

| File                                               | Purpose                                         |
| -------------------------------------------------- | ----------------------------------------------- |
| [`src/api.nix`](src/api.nix)                       | All chainable methods (filter, map, tree, etc.) |
| [`src/collect.nix`](src/collect.nix)               | File collection & filtering logic               |
| [`src/tree.nix`](src/tree.nix)                     | Tree building from directories                  |
| [`src/configTree.nix`](src/configTree.nix)         | NixOS/Home Manager config modules               |
| [`src/flakeModule.nix`](src/flakeModule.nix)       | Flake-parts integration module                  |
| [`src/lib.nix`](src/lib.nix)                       | Internal utilities                              |
| [`src/collect-inputs.nix`](src/collect-inputs.nix) | Collect `__inputs` declarations from files      |

### Overview

| Method                        | Description                          |
| ----------------------------- | ------------------------------------ |
| `imp <path>`                  | Import directory as NixOS module     |
| `.withLib <lib>`              | Bind nixpkgs lib (required for most) |
| `.filter <pred>`              | Filter paths by predicate            |
| `.match <regex>`              | Filter paths by regex                |
| `.map <fn>`                   | Transform matched paths              |
| `.tree <path>`                | Build nested attrset from directory  |
| `.treeWith <lib> <fn> <path>` | Tree with transform                  |
| `.configTree <path>`          | Directory structure → option paths   |
| `.leafs <path>`               | Get list of matched files            |
| `.addAPI <attrset>`           | Extend with custom methods           |
| `.collectInputs <path>`       | Collect `__inputs` from directory    |

### flake-parts Module Options

| Option                    | Type   | Default        | Description                          |
| ------------------------- | ------ | -------------- | ------------------------------------ |
| `imp.src`                 | path   | null           | Directory containing outputs         |
| `imp.args`                | attrs  | {}             | Extra args passed to all files       |
| `imp.perSystemDir`        | string | "perSystem"    | Subdirectory name for per-system     |
| `imp.flakeFile.enable`    | bool   | false          | Enable flake.nix generation          |
| `imp.flakeFile.coreInputs`| attrs  | {}             | Core inputs always in flake.nix      |
| `imp.flakeFile.outputsFile`| string| "./outputs.nix"| Path to outputs file from flake.nix  |

Files in `perSystem/` receive: `{ pkgs, lib, system, self, self', inputs, inputs', ... }`

Files outside `perSystem/` receive: `{ lib, self, inputs, ... }`

## Examples

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

### Collect Inputs

Declare `__inputs` inline where they're used. The flake-parts module collects them automatically:

```nix
# nix/outputs/perSystem/formatter.nix
{
  __inputs.treefmt-nix.url = "github:numtide/treefmt-nix";

  __functor = _: { pkgs, inputs, ... }:
    inputs.treefmt-nix.lib.evalModule pkgs {
      projectRootFile = "flake.nix";
      programs.nixfmt.enable = true;
    };
}
```

```nix
# nix/outputs/homeConfigurations/alice@workstation.nix
{
  __inputs.home-manager = {
    url = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  __functor = _: { inputs, nixpkgs, imp, ... }:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [ (imp ../../home/alice) ];
    };
}
```

Enable flake generation to auto-collect inputs into `flake.nix`:

```nix
# nix/flake/default.nix
inputs:
flake-parts.lib.mkFlake { inherit inputs; } {
  imports = [ inputs.imp.flakeModules.default ];

  imp = {
    src = ../outputs;
    flakeFile = {
      enable = true;
      coreInputs = import ./inputs.nix;
      outputsFile = "./nix/flake";
    };
  };
}
```

```nix
# flake.nix (auto-generated)
{
  inputs = { /* ... */ };
  outputs = inputs: import ./nix/flake inputs;
}
```

Then run `nix run .#gen-flake` to regenerate `flake.nix` with collected inputs.

## Development

```sh
nix run .#tests    # Run unit tests
nix flake check    # Full check
nix fmt            # Format with treefmt
```

## Attribution

- Import features originally written by @vic in [import-tree](https://github.com/vic/import-tree).
- `.collectInputs` inspired by @vic's [flake-file](https://github.com/vic/flake-file).
- `.tree` inspired by [flakelight](https://github.com/nix-community/flakelight)'s autoloading feature.

## License

Apache-2.0 - see [LICENSE](LICENSE).
