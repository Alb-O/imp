# import-tree

Recursively imports Nix modules from a directory tree.

## Quick Start

```nix
{
  inputs.import-tree.url = "github:Alb-O/import-tree";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; }
   (inputs.import-tree ./nix);
}
```

By default, paths containing `/_` are ignored.

## API

### `import-tree <path>`

Takes a path (or nested list of paths) and returns a module importing all `.nix` files found recursively.

```nix
{ imports = [ (import-tree ./nix) ]; }
```

### `.filter` / `.filterNot`

Filter paths by predicate. Multiple filters compose with AND.

```nix
import-tree.filter (lib.hasInfix ".mod.") ./nix
```

### `.match` / `.matchNot`

Filter paths by regex (uses `builtins.match`).

```nix
import-tree.match ".*/[a-z]+@(foo|bar)\.nix" ./nix
```

### `.map`

Transform each matched path.

```nix
import-tree.map (path: { imports = [ path ]; }) ./nix
```

### `.addPath`

Prepend additional paths to search.

```nix
(import-tree.addPath ./vendor) ./nix
```

### `.addAPI`

Extend the import-tree object with custom methods.

```nix
import-tree.addAPI {
  maximal = self: self.addPath ./nix;
  minimal = self: self.maximal.filter (lib.hasInfix "minimal");
}
```

### `.withLib`

Required before using `.leafs` or `.pipeTo` outside module evaluation.

```nix
(import-tree.withLib pkgs.lib).leafs ./nix
```

### `.leafs` / `.files`

Get the list of matched files (requires `.withLib` first).

```nix
(import-tree.withLib lib).files
```

### `.initFilter`

Replace the default filter (`.nix` files, excluding `/_` paths).

```nix
import-tree.initFilter (lib.hasSuffix ".md")
```

### `.new`

Returns a fresh import-tree with empty state.

## Testing

```sh
nix run .#tests
nix flake check
```

## Attribution

Project originally written by @vic under the name `import-tree`: https://github.com/vic/import-tree

## License

Apache-2.0 License, see [LICENSE](LICENSE) file for details.
