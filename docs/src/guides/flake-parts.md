# Using with flake-parts

The flake-parts module turns your directory structure into flake outputs. Point it at an outputs directory and files become attributes.

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    imp.url = "github:imp-nix/imp.lib";
  };

  outputs = inputs@{ flake-parts, imp, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ imp.flakeModules.default ];
      systems = [ "x86_64-linux" "aarch64-linux" ];
      imp = {
        src = ./outputs;
        registry.src = ./registry;  # optional
      };
    };
}
```

## Directory structure

```
outputs/
  perSystem/
    packages.nix      # perSystem.packages
    devShells.nix     # perSystem.devShells
  nixosConfigurations/
    server.nix        # flake.nixosConfigurations.server
  overlays.nix        # flake.overlays
```

Files in `perSystem/` are evaluated once per system in your `systems` list. They receive `pkgs` instantiated for that system, along with `system`, `self'`, and `inputs'` (the per-system projections).

## perSystem files

```nix
# outputs/perSystem/packages.nix
{ pkgs, lib, system, self, self', inputs, inputs', ... }:
{
  hello = pkgs.hello;
  myTool = pkgs.callPackage ./my-tool.nix {};
}
```

These are the standard flake-parts arguments. If you've set `imp.registry.src`, files also receive `imp` and `registry`.

## Flake-level files

Files outside `perSystem/` receive a simpler set of arguments:

```nix
# outputs/nixosConfigurations/server.nix
{ lib, self, inputs, registry, imp, ... }:
lib.nixosSystem {
  system = "x86_64-linux";
  specialArgs = { inherit inputs registry imp; };
  modules = [ /* ... */ ];
}
```

## Adding a registry

```nix
imp = {
  src = ./outputs;
  registry.src = ./registry;
};
```

Now every file receives `registry`, and you can reference modules by name rather than path.

## Multiple directories

imp merges with anything else in your flake-parts config:

```nix
{
  imports = [ imp.flakeModules.default ];
  imp.src = ./outputs;

  # Additional outputs defined directly
  perSystem = { pkgs, ... }: {
    packages.extra = pkgs.hello;
  };
}
```

Manual definitions override imp-loaded ones when both define the same attribute.
