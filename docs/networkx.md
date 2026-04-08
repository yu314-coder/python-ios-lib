# NetworkX

> **Version:** 3.6.1 | **Type:** Stock (pure Python) | **Status:** Fully working

Graph theory and network analysis library. Pure Python — works natively on iOS.

---

## Quick Start

```python
import networkx as nx

G = nx.erdos_renyi_graph(20, 0.3, seed=42)
print(f"Nodes: {G.number_of_nodes()}, Edges: {G.number_of_edges()}")
print(f"Density: {nx.density(G):.3f}")
print(f"Diameter: {nx.diameter(G)}")
print(f"Clustering: {nx.average_clustering(G):.3f}")
```

## Key Functions

### Graph Creation

```python
G = nx.Graph()                        # Undirected
D = nx.DiGraph()                      # Directed
G = nx.complete_graph(10)             # K_10
G = nx.cycle_graph(8)                 # Cycle
G = nx.path_graph(5)                  # Path
G = nx.star_graph(6)                  # Star
G = nx.grid_2d_graph(4, 4)           # Grid
G = nx.erdos_renyi_graph(50, 0.1)    # Random
G = nx.barabasi_albert_graph(50, 2)  # Scale-free
G = nx.watts_strogatz_graph(30, 4, 0.3)  # Small-world
```

### Analysis

| Function | Description |
|----------|-------------|
| `nx.shortest_path(G, s, t)` | Shortest path |
| `nx.shortest_path_length(G, s, t)` | Path length |
| `nx.all_shortest_paths(G, s, t)` | All shortest paths |
| `nx.diameter(G)` | Graph diameter |
| `nx.radius(G)` | Graph radius |
| `nx.is_connected(G)` | Connectivity check |
| `nx.connected_components(G)` | Connected components |
| `nx.degree_centrality(G)` | Degree centrality |
| `nx.betweenness_centrality(G)` | Betweenness centrality |
| `nx.closeness_centrality(G)` | Closeness centrality |
| `nx.pagerank(G)` | PageRank |
| `nx.clustering(G)` | Clustering coefficient |
| `nx.average_clustering(G)` | Average clustering |
| `nx.density(G)` | Graph density |
| `nx.is_eulerian(G)` | Eulerian check |
| `nx.minimum_spanning_tree(G)` | MST (Kruskal) |

### Algorithms

```python
# PageRank
pr = nx.pagerank(G, alpha=0.85)
top5 = sorted(pr.items(), key=lambda x: -x[1])[:5]
print(f"Top 5 by PageRank: {top5}")

# Community detection
communities = nx.community.greedy_modularity_communities(G)
print(f"Communities: {len(communities)}")

# Shortest paths
path = nx.shortest_path(G, source=0, target=5)
print(f"Shortest 0->5: {path}")

# Minimum spanning tree
mst = nx.minimum_spanning_tree(G)
print(f"MST edges: {mst.number_of_edges()}")
```

## Not Available

- Visualization (`nx.draw()` requires matplotlib display backend — use plotly for graph visualization instead)
- GraphML/GML file I/O (filesystem limited on iOS)
