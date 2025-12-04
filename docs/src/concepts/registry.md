# The Registry

Relative paths rot. Today's `../../../modules/nixos/base.nix` works fine until you reorganize, and then you're grepping through files fixing broken imports. The registry solves this by giving modules names.

```nix
# Without registry
imports = [ ../../../modules/nixos/base.nix ];

# With registry
modules = imp.imports [ registry.modules.nixos.base ];
```

The registry maps your directory structure to an attribute set. `registry/modules/nixos/base.nix` becomes `registry.modules.nixos.base`. Move a file and the registry updates automatically; any code using the registry reference keeps working.

## Setup

```nix
imp = {
  src = ../outputs;
  registry.src = ../registry;
};
```

## Structure

The mapping is direct:

```
registry/
  hosts/
    server/default.nix    → registry.hosts.server
  modules/
    nixos/
      base.nix            → registry.modules.nixos.base
      features/
        ssh.nix           → registry.modules.nixos.features.ssh
  users/
    alice/default.nix     → registry.users.alice
```

Directories with `default.nix` become leaf nodes. Directories without it become nested attrsets with a `__path` attribute.

## Usage

Every file loaded by imp receives the `registry` argument:

```nix
{ lib, inputs, imp, registry, ... }:
lib.nixosSystem {
  system = "x86_64-linux";
  specialArgs = { inherit inputs imp registry; };
  modules = imp.imports [
    registry.hosts.server
    registry.modules.nixos.base
    inputs.disko.nixosModules.default  # non-paths pass through
    { services.openssh.enable = true; } # inline config too
  ];
}
```

`imp.imports` handles the translation: registry nodes get their `__path` extracted, paths get imported, and everything else passes through unchanged.

## Importing directories

Sometimes you want every module in a directory:

```nix
imports = [ (imp registry.modules.nixos.features) ];
```

imp recognizes registry nodes with `__path` and imports recursively.

## Overrides

Override specific registry paths with external modules:

```nix
imp.registry.modules = {
  "nixos.disko" = inputs.disko.nixosModules.default;
};
```

This inserts the external module at `registry.modules.nixos.disko`.
