# Naming Conventions

imp translates filesystem paths to Nix attributes. The rules are simple but worth knowing.

| Path              | Attribute   | Notes                      |
| ----------------- | ----------- | -------------------------- |
| `foo.nix`         | `foo`       | File becomes attribute     |
| `foo/default.nix` | `foo`       | Directory with default.nix |
| `foo_.nix`        | `foo`       | Trailing `_` is stripped   |
| `_foo.nix`        | _(ignored)_ | Leading `_` hides files    |

## Directory modules

A directory containing `default.nix` is treated as a single unit. imp imports the `default.nix` and stops; sibling files in that directory are not imported or represented as attributes. They can still be imported by `default.nix` itself using relative paths, giving you a clean external interface while keeping implementation details private.

## Hidden files

Anything starting with `_` is ignored. This covers both files (`_helpers.nix`) and directories (`_internal/`). Use this for helpers that shouldn't be auto-imported, work in progress, or templates meant to be copied rather than evaluated.

## Escaping reserved names

Trailing `_` is stripped from attribute names: `default_.nix` becomes `default`, `import_.nix` becomes `import`. This lets you create attributes that would otherwise conflict with Nix keywords or builtins.

## The `__path` attribute

Directories without `default.nix` include a special `__path` attribute pointing to the directory itself:

```nix
registry.modules.nixos          # Attrset with children + __path
registry.modules.nixos.__path   # Path to the directory
registry.modules.nixos.base     # Path to base.nix
```

When you pass an attrset to `imp`, it checks for `__path` and imports from that directory: `(imp registry.modules.nixos)` recursively imports everything under `registry/modules/nixos/`.
