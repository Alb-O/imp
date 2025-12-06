# Registry Module Pattern

Registry modules can declare flake inputs and overlays inline, alongside the module definition itself. This keeps related concerns together: the module that needs NUR extensions declares the NUR input right there, not in some distant `flake.nix`.

```nix
# nix/registry/modules/home/features/firefox/default.nix
{ inputs, ... }:
{
  __inputs = {
    nur.url = "github:nix-community/NUR";
    nur.inputs.nixpkgs.follows = "nixpkgs";
  };

  __overlays.nur = inputs.nur.overlays.default;

  __module = { config, lib, pkgs, ... }: {
    programs.firefox = {
      enable = true;
      extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
        ublock-origin
        darkreader
      ];
    };
  };
}
```

The file returns a function taking `{ inputs, ... }` and returning an attrset with three special attributes: `__inputs` declares what this module needs in the flake, `__overlays` exports overlays to be applied to nixpkgs, and `__module` contains the actual NixOS/Home-Manager module.

## How `__inputs` Collection Works

When `imp.flakeFile.enable = true`, the flakeModule scans both `imp.src` (outputs directory) and `imp.registry.src` (registry directory) for `__inputs` declarations. This happens in `collect-inputs.nix`.

For plain attrsets, extraction is straightforward: check for `__inputs` attribute and return it. Functions require more work. The collector introspects the function's formal parameters via `builtins.functionArgs`, builds mock arguments that satisfy those parameters, calls the function, and extracts `__inputs` from the result. The mocks in `collect-inputs.nix` cover common patterns: `lib` gets a mock with `mkOption`, `mkIf`, type definitions, and string functions. `pkgs` gets a minimal mock with `system` and `callPackage`. These mocks only need to avoid crashing during evaluation long enough to read `__inputs`.

After collection, `nix run .#imp-flake` regenerates `flake.nix` with all declared inputs merged. Conflicting definitions (same input name, different URL) produce an error listing the conflicting sources.

## How `imp.imports` Extracts `__module`

User configs call `imp.imports` to process a list of registry paths:

```nix
{ registry, imp, lib, ... }:
{
  imports = imp.imports [
    registry.modules.home.base
    registry.modules.home.features.firefox
    registry.modules.home.features.opencode
  ];
}
```

The `imp.imports` function in `api.nix` distinguishes three cases:

1. Registry nodes (attrsets with `__path`): import the path and process
1. Plain paths: import and process
1. Everything else: pass through unchanged

"Processing" means detecting registry wrapper functions and transforming them into standard modules. A registry wrapper is identified by `builtins.functionArgs`: it takes `inputs` but not `config` or `pkgs`. Normal NixOS modules take `{ config, lib, pkgs, ... }`.

For registry wrappers, `imp.imports` returns a replacement function that:

1. Declares common module args explicitly (`config`, `lib`, `pkgs`, `options`, `modulesPath`, `inputs`, `osConfig`) so the module system passes them
1. When called, invokes the original registry wrapper with these args
1. Extracts `__module` from the result
1. Calls `__module` with the same args and returns its result

The explicit arg declaration matters because the NixOS module system uses `builtins.functionArgs` to determine what to pass. A wrapper with just `{ ... }@args` receives nothing useful. Declaring `{ pkgs ? null, lib ? null, ... }@args` ensures the module system provides those values.

## Why Two Function Calls

The original registry wrapper is `{ inputs, ... }: { __inputs; __module }`. When evaluated, it returns an attrset. The `__module` inside is itself a function `{ config, lib, pkgs, ... }: { ... }` expecting module args.

The module system calls a module function once and expects an attrset back. If our wrapper returned `__module` directly, the module system would see a function and fail with "does not look like a module". The wrapper must call both: first the registry wrapper to get `{ __module }`, then `__module` itself to get the final config attrset.

## Overlay Application

The `__overlays` attribute declares overlays this module needs applied to nixpkgs. Collection and application requires explicit wiring. A typical setup has an `overlays.nix` in outputs:

```nix
# nix/outputs/overlays.nix
{ inputs, ... }:
{
  nur = inputs.nur.overlays.default;
}
```

And a base NixOS module that applies them:

```nix
# nix/registry/modules/nixos/base.nix
{ self, lib, ... }:
{
  nixpkgs.overlays = lib.attrValues (self.overlays or { });
}
```

Automatic overlay collection from `__overlays` is not implemented. The declarations serve as documentation and require manual aggregation.

## Limitations

The mock-based input collection cannot handle all code patterns. Functions that eagerly evaluate expressions involving their arguments will fail. The collector uses `builtins.tryEval` and `builtins.deepSeq` to catch errors gracefully, returning empty inputs rather than crashing.

Registry wrapper detection uses a heuristic: "takes `inputs`, not `config` or `pkgs`". A module taking both `inputs` and `config` won't be detected as a registry wrapper and its `__module` won't be extracted. Structure such modules to separate the input-receiving outer function from the config-receiving inner module.
