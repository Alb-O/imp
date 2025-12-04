# Naming Conventions

| Path              | Attribute   | Notes                      |
| ----------------- | ----------- | -------------------------- |
| `foo.nix`         | `foo`       | File becomes attribute     |
| `foo/default.nix` | `foo`       | Directory module           |
| `foo_.nix`        | `foo`       | Trailing `_` escapes names |
| `_foo.nix`        | *(ignored)* | Leading `_` = hidden       |

## Directory modules

A directory with `default.nix` is treated as a single module. Other files in that directory are not visible in the tree (but can be imported by `default.nix`).

## Hidden files

Files starting with `_` are ignored - useful for helpers, WIP files, or templates that are imported manually.

## Escaping reserved names

Trailing `_` is stripped: `default_.nix` → `default`, `import_.nix` → `import`

## `__path` attribute

Directories without `default.nix` include `__path` for importing the whole directory:

```nix
registry.modules.nixos          # Attrset with children + __path
registry.modules.nixos.__path   # Path to the directory
registry.modules.nixos.base     # Path to base.nix
```

## Non-.nix files

Only `.nix` files are collected.
