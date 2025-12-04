# API Methods

<!-- Auto-generated - do not edit -->

## `imp.filter` {#imp.filter}

Filter paths by predicate. Multiple filters compose with AND.

### Example

```nix
imp.filter (lib.hasInfix "/services/") ./modules
imp.filterNot (lib.hasInfix "/deprecated/") ./modules
```

### Arguments

predicate
: Function that receives a path string and returns boolean.

## `imp.filterNot` {#imp.filterNot}

Exclude paths matching predicate. Opposite of filter.

### Example

```nix
imp.filterNot (lib.hasInfix "/deprecated/") ./modules
```

### Arguments

predicate
: Function that receives a path string and returns boolean.

## `imp.match` {#imp.match}

Filter paths by regex. Uses builtins.match.

### Example

```nix
imp.match ".*[/]services[/].*" ./nix
```

### Arguments

regex
: Regular expression string.

## `imp.matchNot` {#imp.matchNot}

Exclude paths matching regex. Opposite of match.

### Example

```nix
imp.matchNot ".*[/]test[/].*" ./src
```

### Arguments

regex
: Regular expression string.

## `imp.initFilter` {#imp.initFilter}

Replace the default filter. By default, imp finds .nix files
and excludes paths containing underscore prefixes.

### Example

```nix
# Import markdown files instead of nix files
imp.initFilter (lib.hasSuffix ".md") ./docs
```

### Arguments

predicate
: Function that receives a path string and returns boolean.

## `imp.map` {#imp.map}

Transform each matched path. Composes with multiple calls.

### Example

```nix
imp.map import ./packages
```

### Arguments

f
: Transformation function applied to each path or value.

## `imp.mapTree` {#imp.mapTree}

Transform values when building a tree with .tree. Composes with multiple calls.

### Example

```nix
(imp.withLib lib)
  .mapTree (drv: drv // { meta.priority = 5; })
  .tree ./packages
```

### Arguments

f
: Transformation function applied to each tree value.

## `imp.withLib` {#imp.withLib}

Provide nixpkgs lib. Required before using .leafs, .files, .tree, or .configTree.

### Example

```nix
imp.withLib pkgs.lib
imp.withLib inputs.nixpkgs.lib
```

### Arguments

lib
: The nixpkgs lib attribute set.

## `imp.addPath` {#imp.addPath}

Add additional paths to search.

### Example

```nix
(imp.withLib lib)
  .addPath ./modules
  .addPath ./vendor
  .leafs
```

### Arguments

path
: Path to add to the search.

## `imp.addAPI` {#imp.addAPI}

Extend imp with custom methods. Methods receive self for chaining.

### Example

```nix
let
  myImp = imp.addAPI {
    services = self: self.filter (lib.hasInfix "/services/");
    packages = self: self.filter (lib.hasInfix "/packages/");
  };
in
myImp.services ./nix
```

### Arguments

api
: Attribute set of name = self: ... methods.

## `imp.pipeTo` {#imp.pipeTo}

Apply a function to the final file list.

### Example

```nix
(imp.withLib lib).pipeTo builtins.length ./modules
```

### Arguments

f
: Function to apply to the file list.

## `imp.leafs` {#imp.leafs}

Get the list of matched files. Requires .withLib.

### Example

```nix
(imp.withLib lib).leafs ./modules
```

## `imp.tree` {#imp.tree}

Build a nested attrset from directory structure. Requires .withLib.

Directory names become attribute names. Files are imported and their
values placed at the corresponding path.

### Example

```nix
(imp.withLib lib).tree ./outputs
# { packages.hello = <imported>; apps.run = <imported>; }
```

### Arguments

path
: Root directory to build tree from.

## `imp.treeWith` {#imp.treeWith}

Convenience function combining .withLib, .mapTree, and .tree.

### Example

```nix
# These are equivalent:
((imp.withLib lib).mapTree (f: f args)).tree ./outputs
imp.treeWith lib (f: f args) ./outputs
```

### Arguments

lib
: The nixpkgs lib attribute set.

f
: Transformation function for tree values.

path
: Root directory to build tree from.

## `imp.configTree` {#imp.configTree}

Build a module where directory structure maps to NixOS option paths.
Each file receives module args and returns config values.

### Example

```nix
{ inputs, lib, ... }: {
  imports = [ ((inputs.imp.withLib lib).configTree ./config) ];
}
# File ./config/programs/git.nix sets config.programs.git
```

### Arguments

path
: Root directory containing config files.

## `imp.configTreeWith` {#imp.configTreeWith}

Like .configTree but passes extra arguments to each file.

### Example

```nix
(imp.withLib lib).configTreeWith { myArg = "value"; } ./config
```

### Arguments

extraArgs
: Additional arguments passed to each config file.

path
: Root directory containing config files.

## `imp.mergeConfigTrees` {#imp.mergeConfigTrees}

Merge multiple config trees into a single module.

### Example

```nix
# Later trees override earlier (default)
(imp.withLib lib).mergeConfigTrees [ ./base ./overrides ]

# With mkMerge semantics
(imp.withLib lib).mergeConfigTrees { strategy = "merge"; } [ ./base ./local ]
```

### Arguments

options (optional)
: Attribute set with strategy ("override" or "merge") and extraArgs.

paths
: List of directories to merge.

## `imp.new` {#imp.new}

Returns a fresh imp instance with empty state, preserving custom API extensions.

### Example

```nix
let
  customImp = imp.addAPI { myMethod = self: self.filter predicate; };
  fresh = customImp.new;
in
fresh.myMethod ./src
```

## `imp.imports` {#imp.imports}

Build a modules list from mixed items. Handles paths, registry nodes, and modules.

### Example

```nix
modules = imp.imports [
  registry.hosts.server
  registry.modules.nixos.base
  ./local-module.nix
  inputs.home-manager.nixosModules.home-manager
  { services.openssh.enable = true; }
];
```

### Arguments

items
: List of paths, registry nodes, or module values.

## `imp.analyze` {#imp.analyze}

Namespace for dependency analysis and visualization.

### Example

```nix
graph = (imp.withLib lib).analyze.registry { registry = myRegistry; }
html = (imp.withLib lib).analyze.toHtml graph
json = (imp.withLib lib).analyze.toJson graph
```

## Registry

## `imp.buildRegistry` {#imp.buildRegistry}

Build registry from a directory.
Returns nested attrset where each directory has \_\_path and child entries.

### Arguments

root
: Root directory path to scan.

## `imp.flattenRegistry` {#imp.flattenRegistry}

Flatten registry to dot-notation paths.

### Example

```nix
flattenRegistry registry
# => { home.alice = <path>; modules.nixos = <path>; modules.nixos.base = <path>; }
```

### Arguments

registry
: Registry attrset to flatten.

## `imp.lookup` {#imp.lookup}

Lookup a dotted path in the registry.

### Example

```nix
lookup "home.alice" registry
# => <path>
```

### Arguments

path
: Dot-separated path string (e.g. "home.alice").

registry
: Registry attrset to search.

## `imp.makeResolver` {#imp.makeResolver}

Create a resolver function that looks up names in the registry.
Returns a function: name -> path

### Example

```nix
resolve = makeResolver registry;
resolve "home.alice"
# => <path>
```

### Arguments

registry
: Registry attrset to create resolver for.

## `imp.toPath` {#imp.toPath}

Get the path from a registry value.
Works for both direct paths and registry nodes with \_\_path.

### Arguments

x
: Registry value (path or node with \_\_path).

## `imp.isRegistryNode` {#imp.isRegistryNode}

Check if a value is a registry node (has \_\_path).

### Arguments

x
: Value to check.

## Format Flake

## `imp.formatValue` {#imp.formatValue}

Format a value as Nix source code.

### Arguments

depth
: Indentation depth level.

value
: Value to format (string, bool, int, null, list, or attrset).

## `imp.formatInput` {#imp.formatInput}

Format a single input definition (at depth 1).

### Arguments

name
: Input name.

def
: Input definition attrset.

## `imp.formatInputs` {#imp.formatInputs}

Format multiple inputs as a block.

### Example

```nix
formatInputs { treefmt-nix = { url = "github:numtide/treefmt-nix"; }; }
# => "treefmt-nix.url = \"github:numtide/treefmt-nix\";"
```

### Arguments

inputs
: Attrset of input definitions.

## `imp.formatFlake` {#imp.formatFlake}

Generate complete flake.nix content.

### Example

```nix
formatFlake {
  description = "My flake";
  coreInputs = { nixpkgs.url = "github:nixos/nixpkgs"; };
  collectedInputs = { treefmt-nix.url = "github:numtide/treefmt-nix"; };
}
```

### Arguments

description
: Flake description string (optional).

coreInputs
: Core flake inputs attrset (optional).

collectedInputs
: Collected inputs from \_\_inputs declarations (optional).

outputsFile
: Path to outputs file (default: "./outputs.nix").

header
: Header comment for generated file (optional).

## Analyze

## `imp.analyzeConfigTree` {#imp.analyzeConfigTree}

Analyze a single configTree, returning nodes and edges.

The path should be a directory. We scan it for .nix files and
read each one to check for registry references.

Note: We only collect refs from files directly in this directory,
not from subdirectories (those are handled as separate nodes).

### Arguments

path
: Directory path to analyze.

id
: Identifier for this config tree node.

## `imp.analyzeMerge` {#imp.analyzeMerge}

Analyze a mergeConfigTrees call.

### Arguments

id
: Identifier for this merged tree.

sources
: List of { id, path } for each source tree.

strategy
: Merge strategy ("merge" or "override").

## `imp.analyzeRegistry` {#imp.analyzeRegistry}

Analyze an entire registry, discovering all modules and their relationships.

This walks the registry structure, finds all configTrees, and analyzes
each one for cross-references. Also generates hierarchical edges between
parent and child nodes (e.g., modules -> modules.home).

### Example

```nix
analyzeRegistry { registry = myRegistry; }
# => { nodes = [...]; edges = [...]; }
```

### Arguments

registry
: Registry attrset to analyze.

## `imp.scanDir` {#imp.scanDir}

Scan a directory and build a list of all .nix files with their logical paths.

### Example

```nix
scanDir ./nix
# => [ { path = /abs/path.nix; segments = ["programs" "git"]; } ... ]
```

### Arguments

root
: Root directory to scan.

## Visualize

## `imp.toHtml` {#imp.toHtml}

Generate interactive HTML visualization using force-graph library.

Features: hover highlighting, cluster coloring, animated dashed directional edges, auto-fix on drag.

### Arguments

graph
: Graph with nodes and edges from analyze functions.

## `imp.toJson` {#imp.toJson}

Convert graph to a JSON-serializable structure with full paths.

### Arguments

graph
: Graph with nodes and edges from analyze functions.

## `imp.toJsonMinimal` {#imp.toJsonMinimal}

Convert graph to JSON without paths (avoids store path issues with special chars).

### Arguments

graph
: Graph with nodes and edges from analyze functions.

## `imp.mkVisualizeScript` {#imp.mkVisualizeScript}

Build a shell script that outputs the graph in the requested format.

Can be called two ways:

1. With pre-computed graph (for flakeModule - fast, no runtime eval):
   mkVisualizeScript { pkgs, graph }

1. With impSrc and nixpkgsFlake (standalone - runtime eval of arbitrary path):
   mkVisualizeScript { pkgs, impSrc, nixpkgsFlake }

### Arguments

pkgs
: nixpkgs package set (for writeShellScript).

graph
: Pre-analyzed graph (optional, for pre-computed mode).

impSrc
: Path to imp source (optional, for standalone mode).

nixpkgsFlake
: Nixpkgs flake reference string (optional, for standalone mode).

name
: Script name (default: "imp-vis").

## Migrate

## `imp.extractRegistryRefs` {#imp.extractRegistryRefs}

Extract all registry.X.Y.Z references from a file's content.
Returns list of dotted paths like [ "home.alice" "modules.nixos" ]

### Arguments

name
: The registry attribute name to search for (e.g., "registry").

content
: String content of the file to search.

## `imp.suggestNewPath` {#imp.suggestNewPath}

Find the best matching new path for an old path.
Uses simple heuristics: matching leaf name, similar structure.

### Arguments

validPaths
: List of currently valid registry paths.

oldPath
: The broken path to find a replacement for.

## `imp.detectRenames` {#imp.detectRenames}

Detect renames by scanning files and comparing against registry.

Returns an attrset containing:

- brokenRefs: list of broken registry references found
- suggestions: attrset mapping old paths to suggested new paths
- affectedFiles: list of files that need updating
- commands: list of ast-grep commands to run
- script: shell script to run all migrations

### Example

```nix
detectRenames {
  registry = myRegistry;
  paths = [ ./nix/outputs ./nix/flake ];
}
```

### Arguments

registry
: The current registry attrset to check against.

paths
: List of paths to scan for registry references.

astGrep
: Path to the ast-grep binary (default: "ast-grep").

registryName
: The attribute name used for the registry (default: "registry").

## Standalone Utilities

## `imp.collectInputs` {#imp.collectInputs}

Scan directories for `__inputs` declarations and collect them.

Recursively scans .nix files for `__inputs` attribute declarations
and merges them into a single attrset. Detects conflicts when the
same input name has different definitions in different files.

### Example

```nix
imp.collectInputs ./outputs
# => { treefmt-nix = { url = "github:numtide/treefmt-nix"; }; }
```

### Arguments

path
: Directory or file path to scan for \_\_inputs declarations.

## `imp.collectAndFormatFlake` {#imp.collectAndFormatFlake}

Convenience function combining collectInputs and formatFlake.

Scans a directory for `__inputs` declarations and generates
complete flake.nix content in one step.

### Example

```nix
imp.collectAndFormatFlake {
  src = ./outputs;
  coreInputs = { nixpkgs.url = "github:nixos/nixpkgs"; };
  description = "My flake";
}
# => "{ description = \"My flake\"; inputs = { ... }; ... }"
```

### Arguments

src
: Directory to scan for \_\_inputs declarations.

coreInputs
: Core flake inputs attrset (optional).

description
: Flake description string (optional).

outputsFile
: Path to outputs file (default: "./outputs.nix").

header
: Header comment for generated file (optional).
