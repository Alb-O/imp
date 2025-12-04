# Documentation structure manifest
# Defines how src/*.nix files are organized into generated docs
{
  # files.md - File reference documentation
  # titleLevel: heading level for the document title (default: 1)
  # Sections are one level below title, files one level below sections
  # Content headings in doc comments are shifted relative to file level
  files = {
    title = "File Reference";
    titleLevel = 1; # H1 for title, H2 for sections, H3 for files, shift by 3 for content

    sections = [
      {
        name = "Core";
        files = [
          "default.nix"
          "api.nix"
          {
            name = "lib.nix";
            fallback = "Internal utility functions for imp.";
          }
        ];
      }
      {
        name = "Import & Collection";
        files = [
          "collect.nix"
          "tree.nix"
        ];
      }
      {
        name = "Config Trees";
        files = [
          "configTree.nix"
          "mergeConfigTrees.nix"
        ];
      }
      {
        name = "Registry";
        files = [
          "registry.nix"
          "migrate.nix"
          "analyze.nix"
          "visualize.nix"
        ];
      }
      {
        name = "Flake Integration";
        files = [
          {
            name = "flakeModule.nix";
            fallback = "flake-parts module, defines `imp.*` options.";
          }
          {
            name = "collect-inputs.nix";
            fallback = "`__inputs` collection from flake inputs.";
          }
          "format-flake.nix"
        ];
      }
    ];
  };

  # methods.md - API method documentation
  # Each entry generates a section with function docs from nixdoc
  methods = {
    title = "API Methods";
    titleLevel = 1; # H1 for title, H2 for section headings

    sections = [
      # No heading = top-level, inherits from title
      { file = "api.nix"; }
      {
        heading = "Registry";
        file = "registry.nix";
      }
      {
        heading = "Format Flake";
        file = "format-flake.nix";
      }
      {
        heading = "Analyze";
        file = "analyze.nix";
      }
      {
        heading = "Visualize";
        file = "visualize.nix";
      }
      {
        heading = "Migrate";
        file = "migrate.nix";
      }
      {
        heading = "Standalone Utilities";
        file = "default.nix";
        exports = [
          "collectInputs"
          "collectAndFormatFlake"
        ];
      }
    ];
  };
}
