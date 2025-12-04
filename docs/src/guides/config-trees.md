# Config Trees

Map directory structure to option paths:

```
home/
  programs/
    git.nix      # -> programs.git = { ... }
    zsh.nix      # -> programs.zsh = { ... }
  services/
    gpg-agent.nix # -> services.gpg-agent = { ... }
```

Each file returns just that option's value:

```nix
# home/programs/git.nix
{
  enable = true;
  userName = "Alice";
}
```

## Usage

```nix
{ inputs, lib, ... }:
{
  imports = [ ((inputs.imp.withLib lib).configTree ./home) ];
}
```

With registry:

```nix
{ imp, ... }:
{
  imports = [ (imp.configTree ./.) ];
}
```

## Files can be functions

```nix
# programs/git.nix
{ pkgs, ... }:
{
  enable = true;
  package = pkgs.gitFull;
}
```

## Directories with default.nix

```
services/
  nginx/
    default.nix   # -> services.nginx = { ... }
```

## Extra arguments

```nix
imp.configTree {
  extraArgs = { myVar = "value"; };
} ./config
```

## When to use

Config trees work well for declarative program/service configuration. Use regular modules for complex logic or options affecting multiple paths.
