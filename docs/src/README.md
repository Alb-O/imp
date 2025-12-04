# Imp 😈

A Nix library for organizing flakes with directory-based imports, named module registries, and automatic input collection.

Primarily inspired by @vic's [Dendritic pattern (and related projects)](https://dendrix.oeiuwq.com/Dendritic.html).

## Installation

```nix
{
  inputs.imp.url = "github:Alb-O/imp";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";
}
```

## Quick Start

As a module importer:

```nix
{ inputs, ... }:
{
  imports = [ (inputs.imp ./nix) ];
}
```

With flake-parts:

```nix
{
  outputs = inputs@{ flake-parts, imp, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ imp.flakeModules.default ];

      systems = [ "x86_64-linux" "aarch64-linux" ];

      imp = {
        src = ./outputs;
        args = { inherit inputs; };
      };
    };
}
```

As a tree builder:

```nix
imp.treeWith lib import ./outputs
# { apps = <...>; packages = { foo = <...>; }; }
```

## Documentation

Full documentation, examples, and API reference, [click here](https://alb-o.github.io/imp).

## Development

```sh
nix run .#tests    # Run unit tests
nix flake check    # Full check
nix fmt            # Format with treefmt
nix run .#docs     # Serve documentation locally
```

## Attribution

- Import features originally from @vic's [import-tree](https://github.com/vic/import-tree)
- `.collectInputs` inspired by @vic's [flake-file](https://github.com/vic/flake-file)
- `.registry` inspired by @vic's [flake-aspects](https://github.com/vic/flake-aspects)
- `.tree` inspired by [flakelight](https://github.com/nix-community/flakelight)'s autoloading

## License

Apache-2.0 - see [LICENSE](LICENSE).
