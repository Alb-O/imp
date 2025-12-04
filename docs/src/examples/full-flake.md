# Full Flake Structure

```
my-flake/
  flake.nix                     # Auto-generated
  nix/
    flake/
      default.nix
      inputs.nix
    outputs/
      nixosConfigurations/
        server.nix
      homeConfigurations/
        alice@workstation.nix
      perSystem/
        packages.nix
        devShells.nix
        formatter.nix           # Uses __inputs
      overlays.nix
    registry/
      hosts/
        server/
          default.nix
          hardware.nix
          config/...
      modules/
        nixos/
          base.nix
          features/...
        home/
          features/
            shell/...
            devTools/...
      users/
        alice/
          default.nix
          programs/...
```

## flake.nix (auto-generated)

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    imp.url = "github:Alb-O/imp";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    # Collected from __inputs
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };
  outputs = inputs: import ./nix/flake inputs;
}
```

## nix/flake/default.nix

```nix
inputs:
flake-parts.lib.mkFlake { inherit inputs; } {
  imports = [ inputs.imp.flakeModules.default ];
  systems = [ "x86_64-linux" "aarch64-linux" ];
  imp = {
    src = ../outputs;
    registry.src = ../registry;
    registry.migratePaths = [ ../outputs ../registry ];
    flakeFile = {
      enable = true;
      coreInputs = import ./inputs.nix;
      outputsFile = "./nix/flake";
    };
  };
}
```

## nix/outputs/perSystem/formatter.nix

```nix
{
  __inputs.treefmt-nix.url = "github:numtide/treefmt-nix";

  __functor = _: { pkgs, inputs, ... }:
    inputs.treefmt-nix.lib.evalModule pkgs {
      projectRootFile = "flake.nix";
      programs.nixfmt.enable = true;
    };
}
```

## nix/outputs/nixosConfigurations/server.nix

```nix
{ lib, inputs, imp, registry, ... }:
lib.nixosSystem {
  system = "x86_64-linux";
  specialArgs = { inherit inputs imp registry; };
  modules = imp.imports [
    registry.hosts.server
    registry.modules.nixos.base
    registry.modules.nixos.features.ssh
  ];
}
```

## nix/registry/users/alice/default.nix

```nix
{ imp, registry, ... }:
{
  imports = [
    registry.modules.home.features.shell
    registry.modules.home.features.devTools
    (imp.configTree ./.)
  ];
  home.username = "alice";
  home.homeDirectory = "/home/alice";
  home.stateVersion = "24.05";
}
```

## Commands

```sh
nixos-rebuild build --flake .#server
home-manager build --flake .#alice@workstation
nix run .#imp-flake      # regenerate flake.nix
nix run .#imp-registry   # check for broken refs
nix run .#imp-vis > deps.html
nix flake check
nix fmt
```
