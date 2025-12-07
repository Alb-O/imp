# Registry Migration

When you rename `home/` to `users/`, the registry structure updates immediately since it derives from the directory tree. But every `registry.home.alice` reference now points to a nonexistent path. The [imp.refactor](https://github.com/imp-nix/imp.refactor) tool detects these broken references and rewrites them.

## Installation

Add imp.refactor to your flake inputs:

```nix
{
  inputs.imp-refactor.url = "github:imp-nix/imp.refactor";
}
```

Or run directly:

```sh
nix run github:imp-nix/imp.refactor -- detect
nix run github:imp-nix/imp.refactor -- apply --write
```

## Usage

From your flake directory:

```sh
# Detect broken refs and show suggestions
imp-refactor detect

# Preview changes (dry-run)
imp-refactor apply

# Apply fixes to files
imp-refactor apply --write

# Interactive mode: confirm each file
imp-refactor apply --interactive
```

## Comparing against previous commits

When comparing working tree files against a previous registry state (before a rename):

```sh
# Compare against previous commit
imp-refactor detect --git-ref HEAD^

# Compare against a branch
imp-refactor detect --git-ref main

# Apply fixes based on old registry
imp-refactor apply --git-ref HEAD^ --write
```

## How it works

The tool scans `.nix` files for `registry.X.Y.Z` patterns using AST parsing (not regex), then checks each against the evaluated registry. Paths that fail lookup are broken references.

For each broken reference, it attempts to find a replacement by matching the leaf name. If `home.alice` is broken and `users.alice` exists, it suggests the mapping. This heuristic works because renames typically preserve the final component.

## Explicit rename mappings

When the leaf-name heuristic fails (ambiguous matches or leaf name changes), supply explicit mappings:

```sh
imp-refactor apply --rename home=users --rename svc.db=services.database --write
```

The longest matching prefix wins, so `--rename home.alice=admins.alice` takes precedence over `--rename home=users` for paths starting with `home.alice`.

## Ambiguous renames

When a leaf name exists in multiple locations, the tool cannot determine which is correct. If you renamed `home/` to `users/` and also created `legacy/alice`, the reference `home.alice` could map to either. These appear with an "ambiguous" reason; use `--rename` to resolve them explicitly.
