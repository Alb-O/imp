/*
  Flake-parts module for imp.

  Automatically loads flake outputs from a directory structure:

    outputs/
      perSystem/
        packages.nix     -> perSystem.packages
        devShells.nix    -> perSystem.devShells
      nixosConfigurations/
        server.nix       -> flake.nixosConfigurations.server
      overlays.nix       -> flake.overlays

  Usage:

    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.imp.flakeModules.default ];

      imp = {
        src = ./outputs;
        args = { inherit inputs; };
      };

      systems = [ "x86_64-linux" "aarch64-linux" ];
    };

  The module passes these arguments to each file:
    - perSystem files: { pkgs, lib, system, self, self', inputs, inputs', ... } // args
    - flake files: { lib, self, inputs, ... } // args

  User-provided args take precedence over module defaults, allowing you to
  override lib with a custom extended version (e.g., nixpkgs.lib).

  Files can be:
    - Functions: called with args, result used as output
    - Attrsets: used directly as output

  ## Flake File Generation

  Enable flake.nix generation from __inputs declarations:

    imp = {
      src = ./outputs;
      flakeFile = {
        enable = true;
        path = ./flake.nix;
        coreInputs = import ./inputs/core.nix;
        description = "My flake";
      };
    };

  Then run `nix run .#gen-flake` to regenerate flake.nix.

  ## Declaring Inputs with __inputs

  Files can declare their required flake inputs inline using `__inputs`.
  These are collected and merged into the generated flake.nix.

  ### With __functor (for files that need args)

  Use this pattern when your output needs access to inputs, pkgs, etc:

    # outputs/perSystem/formatter.nix
    {
      __inputs.treefmt-nix.url = "github:numtide/treefmt-nix";

      __functor = _: { pkgs, inputs, ... }:
        inputs.treefmt-nix.lib.evalModule pkgs { ... };
    }

  The `_:` is required because __functor receives self as first argument.

  ### Without __functor (for static data)

  If your file just returns static data but still declares inputs
  (e.g., for documentation or to ensure the input is available):

    # outputs/overlays.nix
    {
      __inputs.my-overlay-source.url = "github:owner/repo";

      default = final: prev: {
        # overlay contents
      };
    }

  The __inputs are collected, but the rest of the attrset is used as-is.
*/
{
  lib,
  flake-parts-lib,
  config,
  inputs,
  self,
  ...
}:
let
  inherit (lib)
    mkOption
    mkEnableOption
    types
    filterAttrs
    ;

  inherit (flake-parts-lib) mkPerSystemOption;

  impLib = import ./.;

  cfg = config.imp;

  # Build tree from a directory, calling each file with args
  buildTree =
    dir: args:
    if builtins.pathExists dir then
      impLib.treeWith lib (f: if builtins.isFunction f || f ? __functor then f args else f) dir
    else
      { };

  # Determine if a name is a perSystem output
  isPerSystemDir = name: name == cfg.perSystemDir;

  # Get flake-level outputs (everything except perSystem dir)
  flakeTree =
    if cfg.src == null then
      { }
    else
      let
        fullTree = buildTree cfg.src (
          {
            inherit lib self inputs;
          }
          // cfg.args
        );
      in
      filterAttrs (name: _: !isPerSystemDir name) fullTree;

  # Flake file generation
  flakeFileCfg = cfg.flakeFile;
  collectedInputs = if flakeFileCfg.enable then impLib.collectInputs cfg.src else { };
  generatedFlakeContent =
    if flakeFileCfg.enable then
      impLib.formatFlake {
        inherit (flakeFileCfg)
          description
          coreInputs
          outputsFile
          header
          ;
        inherit collectedInputs;
      }
    else
      "";

in
{
  options = {
    imp = {
      src = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Directory containing flake outputs to import";
      };

      args = mkOption {
        type = types.attrsOf types.unspecified;
        default = { };
        description = "Extra arguments passed to all imported files";
      };

      perSystemDir = mkOption {
        type = types.str;
        default = "perSystem";
        description = "Subdirectory name for per-system outputs";
      };

      flakeFile = {
        enable = mkEnableOption "flake.nix generation from __inputs declarations";

        path = mkOption {
          type = types.path;
          default = self + "/flake.nix";
          description = "Path to flake.nix file to generate/check";
        };

        description = mkOption {
          type = types.str;
          default = "";
          description = "Flake description";
        };

        coreInputs = mkOption {
          type = types.attrsOf types.unspecified;
          default = { };
          description = "Core inputs that are always included (e.g., nixpkgs, flake-parts)";
        };

        outputsFile = mkOption {
          type = types.str;
          default = "./outputs.nix";
          description = "Path to outputs.nix (relative to flake.nix)";
        };

        header = mkOption {
          type = types.str;
          default = "# Auto-generated by imp - DO NOT EDIT\n# Regenerate with: nix run .#gen-flake";
          description = "Header comment for generated flake.nix";
        };
      };
    };

    perSystem = mkPerSystemOption (
      { ... }:
      {
        options.imp = {
          args = mkOption {
            type = types.attrsOf types.unspecified;
            default = { };
            description = "Extra per-system arguments passed to imported files";
          };
        };
      }
    );
  };

  config = lib.mkMerge [
    # Main imp config
    (lib.mkIf (cfg.src != null) {
      # Flake-level outputs
      flake = flakeTree;

      # Per-system outputs
      perSystem =
        {
          pkgs,
          system,
          self',
          inputs',
          config,
          ...
        }:
        let
          perSystemPath = cfg.src + "/${cfg.perSystemDir}";
          perSystemArgs = {
            inherit
              lib
              pkgs
              system
              self
              self'
              inputs
              inputs'
              ;
          }
          // cfg.args
          // config.imp.args;
        in
        buildTree perSystemPath perSystemArgs;
    })

    # Flake file generation outputs
    (lib.mkIf flakeFileCfg.enable {
      perSystem =
        { pkgs, ... }:
        {
          # App to regenerate flake.nix
          apps.gen-flake = {
            type = "app";
            program = toString (
              pkgs.writeShellScript "gen-flake" ''
                printf '%s' ${lib.escapeShellArg generatedFlakeContent} > flake.nix
                echo "Generated flake.nix"
              ''
            );
          };

          # Check that flake.nix is up-to-date
          checks.flake-up-to-date =
            pkgs.runCommand "flake-up-to-date"
              {
                expected = generatedFlakeContent;
                actual = builtins.readFile flakeFileCfg.path;
                passAsFile = [
                  "expected"
                  "actual"
                ];
              }
              ''
                if diff -u "$expectedPath" "$actualPath"; then
                  echo "flake.nix is up-to-date"
                  touch $out
                else
                  echo ""
                  echo "ERROR: flake.nix is out of date!"
                  echo "Run 'nix run .#gen-flake' to regenerate it."
                  exit 1
                fi
              '';
        };
    })
  ];
}
