# File Reference

<!-- Auto-generated - do not edit -->

## Core

### default.nix

Entry point for imp - directory-based Nix imports.

This module exports the main imp API including:

- Chainable filtering and transformation methods
- Tree building from directory structure
- Registry for named module discovery
- Utilities for flake input collection

### api.nix

API method definitions for imp.

This module defines all chainable methods available on the imp object.
Methods are organized into categories:

- Filtering: `filter`, `filterNot`, `match`, `matchNot`, `initFilter`
- Transforming: `map`, `mapTree`
- Tree building: `tree`, `treeWith`, `configTree`, `configTreeWith`
- File lists: `leafs`, `files`, `pipeTo`
- Extending: `addPath`, `addAPI`, `withLib`, `new`

### lib.nix

Internal utility functions for imp.

## Import & Collection

### collect.nix

File collection and filtering logic.

This module handles:

- Recursive file discovery from paths
- Filter composition and application
- Path normalization (absolute to relative)

### tree.nix

Builds nested attrset from directory structure.

Naming: `foo.nix` | `foo/default.nix` -> `{ foo = ... }`
`foo_.nix` -> `{ foo = ... }` (escapes reserved names)
`_foo.nix` | `_foo/` -> ignored

#### Example

Directory structure:

```
outputs/
  apps.nix
  checks.nix
  packages/
    foo.nix
    bar.nix
```

```nix
imp.treeWith lib import ./outputs
```

Returns:

```nix
{
  apps = <imported from apps.nix>;
  checks = <imported from checks.nix>;
  packages = {
    foo = <imported from foo.nix>;
    bar = <imported from bar.nix>;
  };
}
```

#### Usage

```nix
(imp.withLib lib).tree ./outputs
```

Or with transform:

```nix
((imp.withLib lib).mapTree (f: f args)).tree ./outputs
imp.treeWith lib (f: f args) ./outputs
```

## Config Trees

### configTree.nix

Builds a NixOS/Home Manager module where directory structure = option paths.

Each file receives module args (`{ config, lib, pkgs, ... }`) plus `extraArgs`,
and returns config values. The path becomes the option path:

- `programs/git.nix` -> `{ programs.git = <result>; }`
- `services/nginx/default.nix` -> `{ services.nginx = <result>; }`

#### Example

Directory structure:

```
home/
  programs/
    git.nix
    zsh.nix
  services/
    syncthing.nix
```

Example file (home/programs/git.nix):

```nix
{ pkgs, ... }: {
  enable = true;
  userName = "Alice";
}
```

#### Usage

```nix
{ inputs, ... }:
{
  imports = [ ((inputs.imp.withLib lib).configTree ./home) ];
}
```

Equivalent to manually writing:

```nix
programs.git = { enable = true; userName = "Alice"; };
programs.zsh = { ... };
services.syncthing = { ... };
```

With extra args:

```nix
((inputs.imp.withLib lib).configTreeWith { myArg = "value"; } ./home)
```

### mergeConfigTrees.nix

Merges multiple config trees into a single NixOS/Home Manager module.

Supports two merge strategies:

- `override` (default): Later trees override earlier (`lib.recursiveUpdate`)
- `merge`: Use module system's `mkMerge` for proper option merging

This enables composable features where one extends another:

```
features/
  shell/programs/{zsh,starship}.nix    # base shell config
  devShell/programs/{git,zsh}.nix      # extends shell, overrides zsh
```

#### Usage

Override strategy (default):

```nix
# devShell/default.nix
{ imp, ... }:
{
  imports = [
    (imp.mergeConfigTrees [ ../shell ./. ])
  ];
}
```

Or with merge strategy for concatenating list options:

```nix
{ imp, ... }:
{
  imports = [
    (imp.mergeConfigTrees { strategy = "merge"; } [ ../shell ./. ])
  ];
}
```

With `override`: later values completely replace earlier ones.
With `merge`: options combine according to module system rules:

- lists concatenate
- strings may error (use `mkForce`/`mkDefault` to control)
- nested attrs merge recursively

## Registry

### registry.nix

Registry: Named module discovery and resolution.

Scans a directory tree and builds a nested attrset mapping names to paths.
Files can then reference modules by name instead of relative paths.

#### Example

Directory structure:

```
nix/
  home/
    alice/default.nix
    bob.nix
  modules/
    nixos/
      base.nix
    home/
      base.nix
```

Produces registry:

```nix
{
  home = {
    __path = <nix/home>;  # directory itself
    alice = <path>;
    bob = <path>;
  };
  modules = {
    __path = <nix/modules>;
    nixos = {
      __path = <nix/modules/nixos>;
      base = <path>;
    };
    home = { ... };
  };
}
```

Usage in files:

```nix
{ registry, ... }:
{
  # Use the directory path
  imports = [ (imp registry.modules.nixos) ];
  # Or a specific file
  imports = [ registry.modules.home.base ];
}
```

Note: Directories are "path-like" (have `__path`) so they work with `imp`.

### analyze.nix

Dependency graph analysis for imp.

Provides functions to analyze config trees and registries, extracting
dependency relationships for visualization.

#### Example

Graph structure:

```nix
{
  nodes = [
    { id = "modules.home.features.shell"; path = /path/to/shell; type = "configTree"; }
    { id = "modules.home.features.devShell"; path = /path/to/devShell; type = "configTree"; }
  ];
  edges = [
    { from = "modules.home.features.devShell"; to = "modules.home.features.shell"; type = "merge"; strategy = "merge"; }
    { from = "modules.home.features.devShell"; to = "modules.home.features.devTools"; type = "merge"; strategy = "merge"; }
  ];
}
```

Usage:

```nix
# Analyze a registry to find all relationships
imp.analyze.registry registry
```

### visualize/default.nix

Visualization output for dependency graphs.

## Export Sinks

### collect-exports.nix

Collects \_\_exports declarations from directory trees.
Standalone implementation - no nixpkgs dependency, only builtins.

Scans `.nix` files recursively for `__exports` attribute declarations and
collects them, tracking source paths for debugging and conflict detection.

Note: Only attrsets with `__exports` are collected. For functions that
need to declare exports, use the `__functor` pattern:

```nix
{
  __exports = {
    "nixos.role.desktop.services" = {
      value = { pipewire.enable = true; };
      strategy = "merge";
    };
  };
  __functor = _: { inputs, ... }: { __module = ...; };
}
```

#### Example

```nix
# Single path
collectExports ./nix/registry
# => {
#   "nixos.role.desktop.services" = [
#     {
#       source = "/nix/registry/mod/nixos/features/desktop/audio.nix";
#       value = { pipewire.enable = true; };
#       strategy = "merge";
#     }
#   ];
# }

# Multiple paths (merged)
collectExports [ ./nix/registry ./nix/features ]
```

#### Arguments

pathOrPaths
: Directory/file path, or list of paths, to scan for \_\_exports declarations.

### export-sinks.nix

Build sinks from collected exports with merge strategy support.

Takes the output from collectExports and produces materialized sinks
by applying merge strategies. Each sink becomes a usable Nix value
(typically a module or attrset).

#### Merge Strategies

- `merge`: Deep merge using lib.recursiveUpdate (last wins for primitives)
- `override`: Last writer completely replaces earlier values
- `list-append`: Concatenate lists (error if non-list)
- `mkMerge`: Use lib.mkMerge for module system semantics (requires lib)

#### Example

```nix
buildExportSinks {
  lib = nixpkgs.lib;
  collected = {
    "nixos.role.desktop" = [
      {
        source = "/path/to/audio.nix";
        value = { services.pipewire.enable = true; };
        strategy = "merge";
      }
      {
        source = "/path/to/wayland.nix";
        value = { services.greetd.enable = true; };
        strategy = "merge";
      }
    ];
  };
  sinkDefaults = {
    "nixos.*" = "merge";
    "hm.*" = "merge";
  };
}
# => {
#   nixos.role.desktop = {
#     __module = { ... merged module ... };
#     __meta = {
#       contributors = [ "/path/to/audio.nix" "/path/to/wayland.nix" ];
#       keys = [ "nixos.role.desktop" ];
#     };
#   };
# }
```

#### Arguments

lib
: nixpkgs lib for merge operations (required for mkMerge strategy).

collected
: Output from collectExports - attrset of sink keys to export records.

sinkDefaults
: Optional attrset mapping glob patterns to default strategies.

enableDebug
: Include \_\_meta with contributor info (default: true).

## Flake Integration

### flakeModule.nix

flake-parts module, defines `imp.*` options.

### collect-inputs.nix

`__inputs` collection from flake inputs.

### format-flake.nix

Formats flake inputs and generates flake.nix content.
Standalone implementation - no nixpkgs dependency, only builtins.

#### Example

```nix
formatInputs { treefmt-nix = { url = "..."; }; }
# => "treefmt-nix = {\n  url = \"...\";\n};\n"

formatFlake {
  description = "My flake";
  coreInputs = { nixpkgs.url = "..."; };
  collectedInputs = { treefmt-nix.url = "..."; };
  outputsFile = "./outputs.nix";
}
# => full flake.nix content as string
```
