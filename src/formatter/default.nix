# Reusable formatter configuration for imp-based flakes
#
# Usage:
#   formatter = imp.formatterLib.make {
#     inherit pkgs treefmt-nix;
#     # Optional overrides:
#     # excludes = [ "vendor/*" ];
#     # extraFormatters = { ... };
#     # nixfmt.enable = false;
#     # mdformat.enable = false;
#     # rust.enable = true;  # enables rustfmt + cargo-sort
#   };
{
  # Create a formatter for the given pkgs and treefmt-nix
  # Returns a derivation suitable for use as `formatter.<system>`
  make =
    {
      pkgs,
      treefmt-nix,
      # Files/directories to exclude from formatting
      excludes ? [ ],
      # Additional treefmt formatter settings (merged with defaults)
      extraFormatters ? { },
      # Enable/disable built-in formatters
      nixfmt ? {
        enable = true;
      },
      mdformat ? {
        enable = true;
      },
      # Rust formatting (rustfmt + cargo-sort) - disabled by default to reduce deps
      rust ? {
        enable = false;
      },
      # Project root file (used by treefmt to find project root)
      projectRootFile ? "flake.nix",
    }:
    let
      lib = pkgs.lib;

      mdformatPkg = pkgs.mdformat.withPlugins (
        ps: with ps; [
          mdformat-gfm
          mdformat-frontmatter
          mdformat-footnote
        ]
      );

      # cargo-sort wrapper that handles treefmt's file-based invocation
      cargo-sort-wrapper = pkgs.writeShellScriptBin "cargo-sort-wrapper" ''
        set -euo pipefail
        opts=()
        files=()
        while [[ $# -gt 0 ]]; do
          case "$1" in
            --*) opts+=("$1"); shift ;;
            *) files+=("$1"); shift ;;
          esac
        done
        for file in "''${files[@]}"; do
          ${lib.getExe pkgs.cargo-sort} "''${opts[@]}" "$(dirname "$file")"
        done
      '';

      mdformatSettings =
        if mdformat.enable then
          {
            mdformat = {
              command = lib.getExe mdformatPkg;
              includes = [ "*.md" ];
            };
          }
        else
          { };

      rustSettings =
        if rust.enable then
          {
            cargo-sort = {
              command = "${cargo-sort-wrapper}/bin/cargo-sort-wrapper";
              options = [ "--workspace" ];
              includes = [
                "Cargo.toml"
                "**/Cargo.toml"
              ];
            };
          }
        else
          { };

      treefmtEval = treefmt-nix.lib.evalModule pkgs {
        inherit projectRootFile;

        programs.nixfmt.enable = nixfmt.enable;
        programs.rustfmt.enable = rust.enable;

        settings.global.excludes = excludes;
        settings.formatter = mdformatSettings // rustSettings // extraFormatters;
      };
    in
    treefmtEval.config.build.wrapper;

  # Convenience function that returns treefmt eval config
  # for use cases where you need the full config, not just wrapper
  makeEval =
    {
      pkgs,
      treefmt-nix,
      excludes ? [ ],
      extraFormatters ? { },
      nixfmt ? {
        enable = true;
      },
      mdformat ? {
        enable = true;
      },
      rust ? {
        enable = false;
      },
      projectRootFile ? "flake.nix",
    }:
    let
      lib = pkgs.lib;

      mdformatPkg = pkgs.mdformat.withPlugins (
        ps: with ps; [
          mdformat-gfm
          mdformat-frontmatter
          mdformat-footnote
        ]
      );

      cargo-sort-wrapper = pkgs.writeShellScriptBin "cargo-sort-wrapper" ''
        set -euo pipefail
        opts=()
        files=()
        while [[ $# -gt 0 ]]; do
          case "$1" in
            --*) opts+=("$1"); shift ;;
            *) files+=("$1"); shift ;;
          esac
        done
        for file in "''${files[@]}"; do
          ${lib.getExe pkgs.cargo-sort} "''${opts[@]}" "$(dirname "$file")"
        done
      '';

      mdformatSettings =
        if mdformat.enable then
          {
            mdformat = {
              command = lib.getExe mdformatPkg;
              includes = [ "*.md" ];
            };
          }
        else
          { };

      rustSettings =
        if rust.enable then
          {
            cargo-sort = {
              command = "${cargo-sort-wrapper}/bin/cargo-sort-wrapper";
              options = [ "--workspace" ];
              includes = [
                "Cargo.toml"
                "**/Cargo.toml"
              ];
            };
          }
        else
          { };
    in
    treefmt-nix.lib.evalModule pkgs {
      inherit projectRootFile;

      programs.nixfmt.enable = nixfmt.enable;
      programs.rustfmt.enable = rust.enable;

      settings.global.excludes = excludes;
      settings.formatter = mdformatSettings // rustSettings // extraFormatters;
    };
}
