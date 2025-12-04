# Collect Inputs

Declare inputs inline where used:

```nix
# outputs/perSystem/formatter.nix
{
  __inputs.treefmt-nix.url = "github:numtide/treefmt-nix";

  __functor = _: { pkgs, inputs, ... }:
    inputs.treefmt-nix.lib.evalModule pkgs {
      projectRootFile = "flake.nix";
      programs.nixfmt.enable = true;
    };
}
```

Imp collects all `__inputs` and generates/updates `flake.nix`.

## Setup

```nix
imp = {
  src = ../outputs;
  flakeFile = {
    enable = true;
    coreInputs = import ./inputs.nix;
    outputsFile = "./nix/flake";
  };
};
```

Core inputs (nixpkgs, flake-parts, etc.) go in `inputs.nix`. Single-use inputs use `__inputs`.

## Regenerate flake.nix

```sh
nix run .#imp-flake
```

## File format

Files with `__inputs` must use `__functor`:

```nix
{
  __inputs = {
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  __functor = _: { pkgs, inputs, ... }:
    inputs.treefmt-nix.lib.evalModule pkgs { /* ... */ };
}
```

## Conflicts

Same input with different URLs across files causes an error. Move shared inputs to `coreInputs`.
