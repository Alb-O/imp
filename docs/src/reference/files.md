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

- Filtering: filter, filterNot, match, matchNot, initFilter
- Transforming: map, mapTree
- Tree building: tree, treeWith, configTree, configTreeWith
- File lists: leafs, files, pipeTo
- Extending: addPath, addAPI, withLib, new

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

Naming: foo.nix | foo/default.nix -> { foo = ... }
foo\_.nix -> { foo = ... } (escapes reserved names)
\_foo.nix | \_foo/ -> ignored

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

Each file receives module args ({ config, lib, pkgs, ... }) plus extraArgs,
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

- "override" (default): Later trees override earlier (lib.recursiveUpdate)
- "merge": Use module system's mkMerge for proper option merging

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

With "override": later values completely replace earlier ones.
With "merge": options combine according to module system rules:

- lists concatenate
- strings may error (use mkForce/mkDefault to control)
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

Note: Directories are "path-like" (have \_\_path) so they work with `imp`.

### migrate.nix

Registry migration: detect renames and generate ast-grep commands to update references.

When directories are renamed, registry paths change. This module:

1. Scans files for registry.X.Y patterns
1. Compares against current registry to find broken references
1. Suggests mappings from old names to new names
1. Generates ast-grep commands to fix all references

#### Usage

```nix
migrate = import ./migrate.nix { inherit lib; };

# Get migration commands
migrate.detectRenames {
  registry = currentRegistry;
  files = [ ./nix/outputs ./nix/flake ];
}
```

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

### visualize.nix

Visualization output for imp dependency graphs.

Provides functions to format analyzed graphs for output:

- toJson: Full JSON with paths
- toJsonMinimal: Minimal JSON without paths
- toHtml: Interactive HTML visualization
- mkVisualizeScript: Shell script for CLI usage

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
