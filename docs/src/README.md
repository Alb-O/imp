# Imp 😈

Nix flakes require explicit imports. Add a module, update the imports list. Reorganize your directory structure, fix every relative path. Imp removes this busywork: point it at a directory and it imports everything inside, automatically inferring and mapping filesystem paths to attribute names.

```nix
{ inputs, ... }:
{
  imports = [ (inputs.imp ./modules) ];
}
```

This imp-frastructure replaces an ever-growing list of explicit imports. Add a file to `modules/`, it gets imported. Remove it, it's no longer imported. No filepath bookkeeping.

## Beyond just imp-orts 😈

Directory-based imports are the foundation, but Imp builds three more things on top:

**Registries** give modules names instead of paths. Instead of `../../../modules/nixos/base.nix`, you write `registry.modules.nixos.base`. Rename a directory and the migration tool scans your codebase for broken `registry.X.Y` references, matches them to new paths by leaf name, and generates ast-grep commands to rewrite them.

**Config trees** map directory structure to NixOS option paths. The file `programs/git.nix` sets `programs.git`. Your directory layout becomes a visual index of what's configured.

**Input collection** scatters flake inputs next to the code that uses them. A formatter module declares its `treefmt-nix` dependency inline; imp collects these and regenerates `flake.nix`.

## Installation

```nix
{
  inputs.imp.url = "github:imp-nix/imp.lib";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";
}
```

## Quick start

With flake-parts (recommended):

```nix
{
  outputs = inputs@{ flake-parts, imp, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ imp.flakeModules.default ];
      systems = [ "x86_64-linux" "aarch64-linux" ];
      imp = {
        src = ./outputs;
        registry.src = ./registry;
      };
    };
}
```

Standalone:

```nix
imp.treeWith lib (f: f { inherit pkgs; }) ./outputs
# { packages.hello = <derivation>; apps.run = <derivation>; }
```

## Documentation

[Full docs](https://imp-nix.github.io/imp.lib)

## Development

```sh
nix run .#tests
nix flake check
nix fmt
nix run .#docs
```

## Attribution

Built on ideas from @vic's [dendritic](https://dendrix.oeiuwq.com/Dendritic.html) pattern, [import-tree](https://github.com/vic/import-tree), [flake-file](https://github.com/vic/flake-file), and [flake-aspects](https://github.com/vic/flake-aspects). Tree building inspired by [flakelight](https://github.com/nix-community/flakelight).

## License

[Apache-2.0](LICENSE)
