# Imp 😈

A Nix library for organizing flakes with directory-based imports, named module registries, and automatic input collection.

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    imp.url = "github:Alb-O/imp";
  };

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

Directory structure becomes configuration:

```
outputs/
  perSystem/
    packages.nix    → perSystem.packages
    devShells.nix   → perSystem.devShells
  nixosConfigurations/
    server.nix      → flake.nixosConfigurations.server

registry/
  hosts/server/     → registry.hosts.server
  modules/nixos/
    base.nix        → registry.modules.nixos.base
```

## Attribution

- Import features from @vic's [import-tree](https://github.com/vic/import-tree)
- `.collectInputs` from @vic's [flake-file](https://github.com/vic/flake-file)
- `.registry` from @vic's [flake-aspects](https://github.com/vic/flake-aspects)
- `.tree` from [flakelight](https://github.com/nix-community/flakelight)

## License

Apache-2.0
