# Registry Migration

Detect broken references after directory renames:

```sh
nix run .#imp-registry           # show what needs fixing
nix run .#imp-registry -- --apply # apply fixes
```

## Example output

```
Detected renames:
  home.alice -> users.alice

Affected files:
  nix/outputs/nixosConfigurations/server.nix

Commands to apply:
  ast-grep --pattern 'registry.home.alice' --rewrite 'registry.users.alice' ...
```

## Configuration

```nix
imp.registry.migratePaths = [ ./outputs ./registry ];
```

## How it works

1. Scans files for `registry.X.Y` patterns
1. Compares against current registry
1. Matches old paths to new by leaf name
1. Uses [ast-grep](https://ast-grep.github.io/) for AST-aware replacements (handles multi-line, ignores comments/strings)

## Ambiguous renames

When a leaf exists in multiple new locations, the tool reports ambiguity for manual resolution.
