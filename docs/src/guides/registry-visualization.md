# Registry Visualization

When your configuration grows complex enough, understanding which modules import what becomes genuinely difficult. The visualization tool generates an interactive dependency graph.

```sh
nix run .#imp-vis > deps.html
nix run .#imp-vis -- --format=json > deps.json
```

Open the HTML file in a browser. You'll see nodes for each registry entry connected by edges representing imports. Hover over a node to highlight its connections. Drag to reposition. Scroll to zoom.

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

## Standalone usage

Outside a flake context:

```sh
nix run github:imp-nix/imp.lib#visualize -- ./path/to/nix > deps.html
```
