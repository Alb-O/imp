# Merging Config Trees

Compose config trees from multiple directories:

```nix
{ imp, registry, ... }:
{
  imports = [
    (imp.mergeConfigTrees [
      registry.modules.home.features.shell
      registry.modules.home.features.devTools
      ./.
    ])
  ];
}
```

## Strategies

### Override (default)

Later values replace earlier ones via `recursiveUpdate`:

```nix
imp.mergeConfigTrees { strategy = "override"; } [ ../base ./. ]
```

### Merge

Values combine via `mkMerge` - lists concatenate, attrs merge deeply:

```nix
imp.mergeConfigTrees { strategy = "merge"; } [ ../base ./. ]
```

Use `lib.mkBefore`/`lib.mkAfter` to control order:

```nix
# programs/zsh.nix
{ lib, ... }:
{
  initContent = lib.mkAfter ''
    export EDITOR="nvim"
  '';
  shellAliases.nb = "nix build";
}
```

## Extra arguments

```nix
imp.mergeConfigTrees {
  strategy = "merge";
  extraArgs = { myVar = "value"; };
} [ ../base ./. ]
```

## Shorthand

```nix
imp.mergeConfigTrees [ ../base ./. ]  # uses "override"
```
