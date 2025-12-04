# Collect Inputs

Flake inputs accumulate at the top of `flake.nix`, divorced from the code that uses them. A formatter needs `treefmt-nix`; that fact is visible only if you read both the inputs block and the formatter definition and connect the dots.

Input collection inverts this. Declare inputs next to the code that uses them:

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

imp scans your codebase for `__inputs` declarations and regenerates `flake.nix` with all of them collected.

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

Core inputs (nixpkgs, flake-parts, imp itself) stay in `inputs.nix` where they belong. Single-use dependencies go in `__inputs` in the same file that references them.

## Regenerating flake.nix

```sh
nix run .#imp-flake
```

Run this after adding or modifying `__inputs` declarations.

## File format

Files using `__inputs` must be attrsets with `__functor`. When imp processes the file, it extracts `__inputs` for the generated `flake.nix` and calls `__functor` to get the actual output value:

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

If two files declare the same input with different URLs, imp errors. Move the shared input to `coreInputs` instead.
