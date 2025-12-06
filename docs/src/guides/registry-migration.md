# Registry Migration

When you rename `home/` to `users/`, the registry structure updates immediately since it derives from the directory tree. But every `registry.home.alice` reference now points to a nonexistent path. The migration tool detects these broken references and generates AST-aware rewrites.

```sh
nix run .#imp-registry           # detect broken refs, show ast-grep commands
nix run .#imp-registry -- --apply # execute rewrites in place
```

## How it works

The tool scans `.nix` files for `registry.X.Y.Z` patterns, then checks each against the current registry. Paths that fail lookup are broken references. By default it scans `imp.src` (your outputs directory); override this if you have registry references elsewhere:

```nix
imp.registry.migratePaths = [ ./outputs ./lib ];
```

For each broken reference, it attempts to find a replacement by matching the leaf name. If `home.alice` is broken and `users.alice` exists, it suggests the mapping. This heuristic works because renames typically preserve the final component.

## AST-aware rewriting

Rather than naive string replacement, the tool generates ast-grep commands that operate on the Nix AST:

```sh
ast-grep --lang nix --pattern 'registry.home.alice' \
  --rewrite 'registry.users.alice' --update-all nix/outputs/*.nix
```

This preserves multi-line expressions, nested attribute access, and formatting while avoiding false matches in comments or string literals.

## Ambiguous renames

When a leaf name exists in multiple locations, the tool cannot determine which is correct. If you renamed `home/` to `users/` and also created `legacy/alice`, the reference `home.alice` could map to either. These appear without a suggested fix; check context and resolve manually.
