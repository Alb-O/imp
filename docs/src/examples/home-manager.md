# Home Manager

```
registry/
  users/
    alice/
      default.nix
      programs/
        git.nix
        zsh.nix
  modules/
    home/
      features/
        shell/
          default.nix
          programs/
            zsh.nix
            starship.nix
        devTools/
          programs/
            git.nix
            neovim.nix
```

## registry/users/alice/default.nix

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

## registry/users/alice/programs/git.nix

```nix
{
  enable = true;
  userName = "Alice Smith";
  userEmail = "alice@example.com";
  extraConfig.init.defaultBranch = "main";
  delta.enable = true;
}
```

## registry/users/alice/programs/zsh.nix

```nix
{ lib, ... }:
{
  shellAliases.projects = "cd ~/projects";
  initContent = lib.mkAfter ''
    export EDITOR="nvim"
  '';
}
```

## registry/modules/home/features/shell/default.nix

```nix
{ imp, ... }:
{
  imports = [ (imp.configTree ./.) ];
}
```

## registry/modules/home/features/shell/programs/zsh.nix

```nix
{
  enable = true;
  enableCompletion = true;
  autosuggestion.enable = true;
  syntaxHighlighting.enable = true;
  history = { size = 10000; ignoreDups = true; };
  shellAliases = { ll = "ls -la"; ".." = "cd .."; };
}
```

## With mergeConfigTrees

```nix
{ imp, registry, ... }:
{
  imports = [
    (imp.mergeConfigTrees { strategy = "merge"; } [
      registry.modules.home.features.shell
      registry.modules.home.features.devTools
      ./.
    ])
  ];
  home.username = "alice";
  home.homeDirectory = "/home/alice";
  home.stateVersion = "24.05";
}
```

## outputs/homeConfigurations/alice@workstation.nix

```nix
{ inputs, nixpkgs, imp, registry, ... }:
inputs.home-manager.lib.homeManagerConfiguration {
  pkgs = nixpkgs.legacyPackages.x86_64-linux;
  extraSpecialArgs = { inherit inputs imp registry; };
  modules = [ (import registry.users.alice) ];
}
```
