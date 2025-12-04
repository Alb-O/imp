# Directory-Based Imports

Point imp at a directory to import all `.nix` files recursively:

```nix
{ inputs, ... }:
{
  imports = [ (inputs.imp ./modules) ];
}
```

Equivalent to:

```nix
{
  imports = [
    ./modules/networking.nix
    ./modules/users/alice.nix
    ./modules/users/bob.nix
    ./modules/services/nginx.nix
  ];
}
```

## Filtering

```nix
let imp = inputs.imp.withLib lib; in
{
  imports = [
    (imp.filter (lib.hasInfix "/services/") ./modules)
    (imp.filterNot (lib.hasSuffix ".test.nix") ./modules)
    (imp.match ".*/(users|groups)/.*" ./modules)
  ];
}
```

## Getting file list

```nix
imp.leafs ./modules
# => [ "/path/to/modules/networking.nix" ... ]
```
