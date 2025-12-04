# Registry Migration

You rename `home/` to `users/`. The registry structure updates immediately since it's derived from the directory tree, but now every `registry.home.alice` reference in your codebase points to a path that no longer exists.

```sh
nix run .#imp-registry           # detect broken refs, print ast-grep commands
nix run .#imp-registry -- --apply # execute the rewrites, modifying files in place
```

## Detection

The migration tool reads each `.nix` file in your configured paths, extracts strings matching `registry.X.Y.Z` via line-by-line regex, then checks each extracted path against the current registry attrset. Any path that fails lookup is a broken reference.

```nix
imp.registry.migratePaths = [ ./outputs ./registry ];
```

For each broken reference, the tool attempts to find a replacement by matching the leaf name. If `home.alice` is broken and `users.alice` exists in the current registry, it suggests `home.alice -> users.alice`. This heuristic works because renames typically preserve the final component.

## Rewriting with ast-grep

Rather than naive string replacement (which would break inside comments and string literals), the tool generates ast-grep commands that operate on the Nix AST:

```sh
ast-grep --lang nix --pattern 'registry.home.alice' \
  --rewrite 'registry.users.alice' --update-all nix/outputs/*.nix
```

ast-grep parses each file, matches the pattern as an AST node, and replaces only actual code references. Multi-line expressions, nested attribute access, and complex formatting are preserved.

## Example session

```
$ nix run .#imp-registry

Registry Migration
==================

Detected renames:
  home.alice -> users.alice
  home.bob -> users.bob

Affected files:
  nix/outputs/nixosConfigurations/server.nix
  nix/outputs/nixosConfigurations/workstation.nix

Commands to apply:
  ast-grep --pattern 'registry.home.alice' --rewrite 'registry.users.alice' ...
  ast-grep --pattern 'registry.home.bob' --rewrite 'registry.users.bob' ...

Run with --apply to execute these commands.
```

Running with `--apply` executes each ast-grep command with `--update-all`, modifying files in place.

## Ambiguous renames

When the leaf name exists in multiple locations, the tool cannot determine which is correct. If you renamed both `home/` to `users/` and created a new `legacy/alice`, the reference `home.alice` could map to either `users.alice` or `legacy.alice`.

These appear in the broken refs list without a suggested fix. Check the context of each reference to determine the correct target, then either rename to disambiguate or fix manually.
