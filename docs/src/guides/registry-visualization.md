# Registry Visualization

When your configuration grows complex enough, understanding which modules import what becomes genuinely difficult. The visualization tool generates an interactive dependency graph.

## Setup

Visualization requires the `imp-graph` input. Add it to your flake and import the visualization module:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    imp.url = "github:imp-nix/imp.lib";
    imp-graph.url = "github:imp-nix/imp.graph";
    imp-graph.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ flake-parts, imp, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        imp.flakeModules.default
        imp.flakeModules.visualize
      ];
      imp = {
        src = ./outputs;
        registry.src = ./registry;
      };
    };
}
```

The module activates automatically when it detects the `imp-graph` input. This adds two apps: `visualize` (a standalone tool) and `imp-vis` (which uses your configured registry).

## Usage

```sh
nix run .#imp-vis > deps.html
nix run .#imp-vis -- --format=json > deps.json
```

Open the HTML file in a browser. Nodes represent registry entries, connected by edges for each `registry.X.Y` reference found in source files. Hover over a node to highlight its connections. Drag to reposition. Scroll to zoom.

The standalone `visualize` app works without registry configuration:

```sh
nix run .#visualize -- ./path/to/nix > deps.html
```

## Reading the graph

Nodes are colored by cluster (hosts, modules.home, modules.nixos). Sink nodes (final outputs like nixosConfigurations) appear larger with labels. Nodes with identical edge topology are merged to reduce visual clutter.

Edges show `registry.X.Y` references found in each file. A dashed edge from `hosts.server` to `modules.nixos.base` means the server host imports that base module.

## JSON format

For programmatic access:

```json
{
  "nodes": [{ "id": "hosts.server", "cluster": "hosts" }],
  "edges": [{ "from": "hosts.server", "to": "modules.nixos.base" }]
}
```
