# Imp 😈

A Nix library for organizing flakes with directory-based imports, named module registries, and automatic input collection.

Primarily inspired by @vic's [Dendritic pattern (and related projects)](https://dendrix.oeiuwq.com/Dendritic.html).

## Installation

Add `imp` as a flake input:

```nix
{
  inputs.imp.url = "github:Alb-O/imp";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";
}
```

## Quick Start

### As a Module Importer

```nix
{ inputs, ... }:
{
  imports = [ (inputs.imp ./nix) ];
}
```

### With flake-parts

`imp` provides a flake-parts module that auto-loads outputs from a directory:

```nix
{
  outputs = inputs@{ flake-parts, imp, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ imp.flakeModules.default ];

      systems = [ "x86_64-linux" "aarch64-linux" ];

      imp = {
        src = ./outputs;            # Directory to load
        args = { inherit inputs; }; # Extra args for all files
      };
    };
}
```

Directory structure:

```
outputs/
  perSystem/
    packages.nix      -> perSystem.packages (receives pkgs, system, etc.)
    devShells.nix     -> perSystem.devShells
  nixosConfigurations/
    server.nix        -> flake.nixosConfigurations.server
  overlays.nix        -> flake.overlays
```

Files in `perSystem/` receive: `{ pkgs, lib, system, self, self', inputs, inputs', registry, ... }`

Files outside `perSystem/` receive: `{ lib, self, inputs, registry, ... }`

### As a Tree Builder

```nix
# outputs/
#   apps.nix
#   packages/
#     foo.nix

imp.treeWith lib import ./outputs
# { apps = <...>; packages = { foo = <...>; }; }
```

## Naming Conventions

| Path              | Attribute | Notes                               |
| ----------------- | --------- | ----------------------------------- |
| `foo.nix`         | `foo`     | File as module                      |
| `foo/default.nix` | `foo`     | Directory module                    |
| `foo_.nix`        | `foo`     | Trailing `_` escapes reserved names |
| `_foo.nix`        | (ignored) | Leading `_` = hidden                |

## API

Full API documentation with examples is inline in the source code (`src/`).

Click to expand overview sections below:

<details>
  <summary>File references</summary>

| File                                                   | Purpose                                         |
| ------------------------------------------------------ | ----------------------------------------------- |
| [`src/api.nix`](src/api.nix)                           | All chainable methods (filter, map, tree, etc.) |
| [`src/collect.nix`](src/collect.nix)                   | File collection & filtering logic               |
| [`src/tree.nix`](src/tree.nix)                         | Tree building from directories                  |
| [`src/registry.nix`](src/registry.nix)                 | Named module discovery and resolution           |
| [`src/migrate.nix`](src/migrate.nix)                   | Registry rename detection and migration         |
| [`src/configTree.nix`](src/configTree.nix)             | NixOS/Home Manager config modules               |
| [`src/mergeConfigTrees.nix`](src/mergeConfigTrees.nix) | Merge multiple config trees                     |
| [`src/flakeModule.nix`](src/flakeModule.nix)           | Flake-parts integration module                  |
| [`src/lib.nix`](src/lib.nix)                           | Internal utilities                              |
| [`src/collect-inputs.nix`](src/collect-inputs.nix)     | Collect `__inputs` declarations from files      |

</details >

<details>
  <summary>Methods</summary>

| Method                        | Description                          |
| ----------------------------- | ------------------------------------ |
| `imp <path>`                  | Import directory as NixOS module     |
| `.withLib <lib>`              | Bind nixpkgs lib (required for most) |
| `.filter <pred>`              | Filter paths by predicate            |
| `.match <regex>`              | Filter paths by regex                |
| `.map <fn>`                   | Transform matched paths              |
| `.tree <path>`                | Build nested attrset from directory  |
| `.treeWith <lib> <fn> <path>` | Tree with transform                  |
| `.configTree <path>`          | Directory structure → option paths   |
| `.mergeConfigTrees <paths>`   | Merge multiple config trees          |
| `.leafs <path>`               | Get list of matched files            |
| `.addAPI <attrset>`           | Extend with custom methods           |
| `.collectInputs <path>`       | Collect `__inputs` from directory    |
| `.registry <path>`            | Build named module registry          |

</details >

<details>
  <summary>Module options</summary>

| Option                      | Type   | Default         | Description                         |
| --------------------------- | ------ | --------------- | ----------------------------------- |
| `imp.src`                   | path   | null            | Directory containing outputs        |
| `imp.args`                  | attrs  | {}              | Extra args passed to all files      |
| `imp.perSystemDir`          | string | "perSystem"     | Subdirectory name for per-system    |
| `imp.registry.name`         | string | "registry"      | Attribute name for registry arg     |
| `imp.registry.src`          | path   | null            | Root directory for module registry  |
| `imp.registry.modules`      | attrs  | {}              | Explicit name->path overrides       |
| `imp.registry.migratePaths` | list   | []              | Directories to scan for renames     |
| `imp.flakeFile.enable`      | bool   | false           | Enable flake.nix generation         |
| `imp.flakeFile.coreInputs`  | attrs  | {}              | Core inputs always in flake.nix     |
| `imp.flakeFile.outputsFile` | string | "./outputs.nix" | Path to outputs file from flake.nix |

</details >

## Examples

### Config Tree (Home Manager / NixOS)

Directory structure becomes option paths:

```
home/
  programs/
    git.nix      -> programs.git = { ... }
    zsh.nix      -> programs.zsh = { ... }
```

```nix
{ inputs, ... }:
{
  imports = [ ((inputs.imp.withLib lib).configTree ./home) ];
}
```

### Merge Config Trees (Composable Features)

Combine multiple config trees into one, with control over how values merge:

```
features/
  shell/
    programs/
      zsh.nix        # enable=true, shellAliases={...}
      starship.nix
  devTools/
    programs/
      git.nix
      neovim.nix
  devShell/
    default.nix      # Merges shell + devTools + local additions
    programs/
      zsh.nix        # Additional aliases, initContent
```

```nix
# features/devShell/default.nix
{ imp, registry, ... }:
{
  imports = [
    (imp.mergeConfigTrees { strategy = "merge"; } [
      registry.modules.home.features.shell     # base shell config
      registry.modules.home.features.devTools  # dev tools
      ./.                                       # local additions/overrides
    ])
  ];
}
```

**Merge strategies:**

| Strategy     | Behavior                                         | Use case                              |
| ------------ | ------------------------------------------------ | ------------------------------------- |
| `"override"` | Later values replace earlier (`recursiveUpdate`) | Override specific settings            |
| `"merge"`    | Module system semantics (`mkMerge`)              | Concatenate lists, merge attrs deeply |

With `"override"` (default), if both `shell` and `devShell` define `programs.zsh.initContent`, the later one wins completely.

With `"merge"`, `initContent` values are concatenated (since it's a `types.lines` option). Use `lib.mkBefore`/`lib.mkAfter` to control ordering:

```nix
# features/devShell/programs/zsh.nix
{ lib, ... }:
{
  shellAliases = {
    nb = "nix build";
    nd = "nix develop";
  };

  # Appended after shell's initContent
  initContent = lib.mkAfter ''
    export EDITOR="nvim"
  '';
}
```

**Simple usage (no options):**

```nix
# Default: override strategy
imp.mergeConfigTrees [ ../base ./. ]
```

**With options:**

```nix
imp.mergeConfigTrees {
  strategy = "merge";           # or "override"
  extraArgs = { foo = "bar"; }; # passed to all config files
} [ ../base ./. ]
```

### Conditional Loading

```nix
let
  imp = inputs.imp.withLib lib;
in
{
  imports = [
    (if isServer
      then imp.filter (lib.hasInfix "/server/") ./modules
      else imp.filter (lib.hasInfix "/desktop/") ./modules)
  ];
}
```

### Registry (Named Module Resolution)

Reference modules by name instead of relative paths. The registry maps directory structure to named modules:

```
nix/
  home/
    alice/default.nix  -> registry.home.alice
  modules/
    nixos/             -> registry.modules.nixos (directory path)
      base.nix         -> registry.modules.nixos.base
    home/
      base.nix         -> registry.modules.home.base
  hosts/
    server/default.nix -> registry.hosts.server
```

Enable the registry in flake-parts:

```nix
# nix/flake/default.nix
inputs:
let
  impLib = inputs.imp.withLib nixpkgs.lib;
  registry = impLib.registry ./..;  # Build registry from nix/ directory
in
flake-parts.lib.mkFlake { inherit inputs; } {
  imports = [ inputs.imp.flakeModules.default ];

  imp = {
    src = ../outputs;
    registry.src = ./..;  # Auto-inject registry into all files
  };

  flake.nixosModules.default = imp registry.modules.nixos;
}
```

Use registry in output files:

```nix
# nix/outputs/nixosConfigurations/server.nix
{ inputs, lib, imp, registry, ... }:
lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    (imp registry.hosts.server)
    (imp registry.modules.nixos)
  ];
}
```

Directories without `default.nix` include a `__path` attribute for the directory itself, plus entries for children. This lets you use `imp registry.modules.nixos` to import the whole directory, or `registry.modules.nixos.base` for a specific file.

### Registry Migration

When directories are renamed, registry paths change. The `imp-registry` app detects broken references and generates fix commands:

```sh
# Detect renames and see suggestions
nix run .#imp-registry

# Apply fixes automatically
nix run .#imp-registry -- --apply
```

Example output after renaming `home/` to `users/`:

```
Registry Migration
==================

Detected renames:
  home.alice -> users.alice

Affected files:
  nix/outputs/nixosConfigurations/server.nix

Commands to apply:
  ast-grep --lang nix --pattern 'registry.home.alice' --rewrite 'registry.users.alice' nix/outputs/...

Run with --apply to execute these commands.
```

The tool:
1. Scans files for `registry.X.Y` patterns
2. Compares against current registry to find broken references
3. Matches old paths to new paths by leaf name (e.g., `home.alice` → `users.alice`)
4. Uses [ast-grep](https://ast-grep.github.io/) for AST-aware replacements (handles multi-line expressions correctly)

### Collect Inputs

Declare `__inputs` inline where they're used. The flake-parts module collects them automatically:

```nix
# nix/outputs/perSystem/formatter.nix
{
  __inputs.treefmt-nix.url = "github:numtide/treefmt-nix";

  __functor = _: { pkgs, inputs, ... }:
    inputs.treefmt-nix.lib.evalModule pkgs {
      projectRootFile = "flake.nix";
      programs.nixfmt.enable = true;
    };
}
```

```nix
# nix/outputs/homeConfigurations/alice@workstation.nix
{
  __inputs.home-manager = {
    url = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  __functor = _: { inputs, nixpkgs, imp, registry, ... }:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [ (imp registry.home.alice) ];
    };
}
```

Enable flake generation to auto-collect inputs into `flake.nix`:

```nix
# nix/flake/default.nix
inputs:
flake-parts.lib.mkFlake { inherit inputs; } {
  imports = [ inputs.imp.flakeModules.default ];

  imp = {
    src = ../outputs;
    flakeFile = {
      enable = true;
      coreInputs = import ./inputs.nix;
      outputsFile = "./nix/flake";
    };
  };
}
```

```nix
# flake.nix (auto-generated)
{
  inputs = { /* ... */ };
  outputs = inputs: import ./nix/flake inputs;
}
```

Then run `nix run .#imp-flake` to regenerate `flake.nix` with collected inputs.

## Development

```sh
nix run .#tests    # Run unit tests
nix flake check    # Full check
nix fmt            # Format with treefmt
```

## Attribution

- Import features originally written by @vic in [import-tree](https://github.com/vic/import-tree).
- `.collectInputs` inspired by @vic's [flake-file](https://github.com/vic/flake-file).
- `.registry` inspired by @vic's [flake-aspects](https://github.com/vic/flake-aspects).
- `.tree` inspired by [flakelight](https://github.com/nix-community/flakelight)'s autoloading feature.

## License

Apache-2.0 - see [LICENSE](LICENSE).
