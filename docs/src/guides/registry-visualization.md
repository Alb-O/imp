# Registry Visualization

Generate an interactive dependency graph:

```sh
nix run .#imp-vis > deps.html
nix run .#imp-vis -- --format=json > deps.json
```

## The graph

- **Nodes**: registry entries
- **Edges**: `registry.X.Y` references
- **Colors**: clusters (modules.home, hosts, etc.)
- **Sink nodes**: final outputs (nixosConfigurations), shown larger with labels

Nodes with identical edge topology are merged to reduce clutter.

## Interaction

Hover to highlight connections. Drag to reposition. Scroll to zoom.

## JSON format

```json
{
  "nodes": [{ "id": "hosts.server", "cluster": "hosts" }],
  "edges": [{ "from": "hosts.server", "to": "modules.nixos.base" }]
}
```

## Standalone

```sh
nix run .#visualize -- ./path/to/nix > deps.html
```
