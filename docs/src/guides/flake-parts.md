# Using with flake-parts

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
        args = { inherit inputs; };
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

## perSystem files

```nix
# outputs/perSystem/packages.nix
{ pkgs, lib, system, self, self', inputs, inputs', ... }:
{
  hello = pkgs.hello;
}
```

## Non-perSystem files

```nix
# outputs/nixosConfigurations/server.nix
{ lib, self, inputs, registry, imp, ... }:
lib.nixosSystem {
  system = "x86_64-linux";
  specialArgs = { inherit inputs registry imp; };
  modules = [ /* ... */ ];
}
```

## With registry

```nix
imp = {
  src = ./outputs;
  registry.src = ./registry;
};
```

## Multiple directories

```nix
{
  imports = [ imp.flakeModules.default ];
  imp.src = ./outputs;
  imports = [ (import ./extra-outputs { inherit inputs; }) ];
}
```

Imp-loaded outputs merge with manual definitions.
