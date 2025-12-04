# Basic Import

```
modules/
  networking.nix
  users/
    alice.nix
    bob.nix
  services/
    ssh.nix
```

## Usage

```nix
{ inputs, ... }:
{
  imports = [ (inputs.imp ./modules) ];
}
```

## In a flake

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    imp.url = "github:Alb-O/imp";
  };

  outputs = { nixpkgs, imp, ... }:
    {
      nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          (imp ./modules)
          ./hardware-configuration.nix
        ];
      };
    };
}
```

## Module files

```nix
# modules/networking.nix
{ ... }:
{
  networking.hostName = "myhost";
  networking.networkmanager.enable = true;
}
```

## Filtering

```nix
let imp = inputs.imp.withLib lib; in
{
  imports = [ (imp.filter (lib.hasInfix "/services/") ./modules) ];
}
```
