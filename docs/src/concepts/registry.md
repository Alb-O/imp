# The Registry

Named access to modules instead of relative paths:

```nix
# Without registry
imports = [ ../../../modules/nixos/base.nix ];

# With registry
modules = imp.imports [ registry.modules.nixos.base ];
```

## Setup

```nix
imp = {
  src = ../outputs;
  registry.src = ../registry;
};
```

## Structure

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

## Usage

The `registry` argument is passed to all files:

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

## Importing directories

```nix
imports = [ (imp registry.modules.nixos.features.__path) ];
# or
imports = [ (imp registry.modules.nixos.features) ];
```

## Overrides

```nix
imp.registry.modules = {
  "nixos.disko" = inputs.disko.nixosModules.default;
};
```
