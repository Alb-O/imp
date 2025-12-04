# Getting Started

Add imp to your flake:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    imp.url = "github:Alb-O/imp";
  };
}
```

## With flake-parts

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

```
outputs/
  perSystem/
    packages.nix      # -> perSystem.packages
    devShells.nix     # -> perSystem.devShells
  nixosConfigurations/
    server.nix        # -> flake.nixosConfigurations.server
  overlays.nix        # -> flake.overlays
```

## As a module importer

```nix
{ inputs, ... }:
{
  imports = [ (inputs.imp ./nix) ];
}
```

## As a tree builder

```nix
imp.treeWith lib import ./outputs
# => { apps = <...>; packages = { foo = <...>; }; }
```

## Arguments passed to files

In `perSystem/`: `pkgs`, `lib`, `system`, `self`, `self'`, `inputs`, `inputs'`, `registry`, `imp`

Outside `perSystem/`: `lib`, `self`, `inputs`, `registry`, `imp`
