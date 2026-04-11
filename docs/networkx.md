# NetworkX

> **Version:** 3.6.1 | **Type:** Stock (pure Python) | **Status:** Fully working

Graph theory and network analysis library. Pure Python -- works natively on iOS.

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

---

## Graph Types

| Class | Description |
|-------|-------------|
| `nx.Graph()` | Undirected graph (no parallel edges) |
| `nx.DiGraph()` | Directed graph |
| `nx.MultiGraph()` | Undirected multigraph (parallel edges allowed) |
| `nx.MultiDiGraph()` | Directed multigraph |

---

## Graph Creation

### From Scratch

```python
G = nx.Graph()
G.add_node(1, label="A")
G.add_nodes_from([2, 3, 4])
G.add_edge(1, 2, weight=3.5)
G.add_edges_from([(2, 3), (3, 4, {"weight": 1.0})])
G.add_weighted_edges_from([(1, 3, 2.0), (2, 4, 4.0)])
```

### Graph Generators

| Function | Description |
|----------|-------------|
| `nx.complete_graph(n)` | Complete graph K_n |
| `nx.cycle_graph(n)` | Cycle C_n |
| `nx.path_graph(n)` | Path P_n |
| `nx.star_graph(n)` | Star S_n (center + n leaves) |
| `nx.wheel_graph(n)` | Wheel W_n |
| `nx.grid_2d_graph(m, n)` | 2D grid |
| `nx.grid_graph(dim)` | N-dimensional grid |
| `nx.hypercube_graph(n)` | N-dimensional hypercube |
| `nx.complete_bipartite_graph(n1, n2)` | Complete bipartite K_{n1,n2} |
| `nx.circular_ladder_graph(n)` | Circular ladder |
| `nx.ladder_graph(n)` | Ladder graph |
| `nx.petersen_graph()` | Petersen graph |
| `nx.tutte_graph()` | Tutte graph |
| `nx.dodecahedral_graph()` | Dodecahedral graph |
| `nx.icosahedral_graph()` | Icosahedral graph |
| `nx.octahedral_graph()` | Octahedral graph |
| `nx.cubical_graph()` | Cubical graph |
| `nx.karate_club_graph()` | Zachary's karate club |
| `nx.davis_southern_women_graph()` | Davis southern women |
| `nx.les_miserables_graph()` | Les Miserables character network |
| `nx.balanced_tree(r, h)` | Balanced r-ary tree of height h |
| `nx.full_rary_tree(r, n)` | Full r-ary tree with n nodes |
| `nx.binomial_tree(n)` | Binomial tree of order n |

### Random Graph Generators

| Function | Description |
|----------|-------------|
| `nx.erdos_renyi_graph(n, p, seed)` | Erdos-Renyi G(n,p) random graph |
| `nx.gnm_random_graph(n, m, seed)` | Random graph with n nodes, m edges |
| `nx.barabasi_albert_graph(n, m, seed)` | Barabasi-Albert preferential attachment |
| `nx.watts_strogatz_graph(n, k, p, seed)` | Watts-Strogatz small-world |
| `nx.newman_watts_strogatz_graph(n, k, p)` | Newman-Watts-Strogatz |
| `nx.powerlaw_cluster_graph(n, m, p)` | Power-law cluster graph |
| `nx.random_regular_graph(d, n)` | Random d-regular graph |
| `nx.random_geometric_graph(n, radius)` | Random geometric graph |
| `nx.stochastic_block_model(sizes, p)` | Stochastic block model |
| `nx.random_tree(n)` | Random labeled tree |
| `nx.random_lobster(n, p1, p2)` | Random lobster graph |

---

## Graph Properties

| Function | Description |
|----------|-------------|
| `G.number_of_nodes()` / `len(G)` | Node count |
| `G.number_of_edges()` | Edge count |
| `G.nodes()` / `G.nodes(data=True)` | Node iterator (with attributes) |
| `G.edges()` / `G.edges(data=True)` | Edge iterator (with attributes) |
| `G.adj[n]` / `G[n]` | Neighbors of node n |
| `G.degree(n)` / `G.degree()` | Node degree(s) |
| `G.has_node(n)` | Check if node exists |
| `G.has_edge(u, v)` | Check if edge exists |
| `G.neighbors(n)` | Iterator over neighbors |
| `G.successors(n)` | Successors (DiGraph) |
| `G.predecessors(n)` | Predecessors (DiGraph) |
| `G.in_degree(n)` | In-degree (DiGraph) |
| `G.out_degree(n)` | Out-degree (DiGraph) |

---

## Shortest Paths

| Function | Description |
|----------|-------------|
| `nx.shortest_path(G, source, target, weight)` | Single shortest path |
| `nx.shortest_path_length(G, source, target, weight)` | Path length |
| `nx.all_shortest_paths(G, source, target)` | All shortest paths |
| `nx.all_pairs_shortest_path(G)` | All-pairs shortest paths |
| `nx.all_pairs_shortest_path_length(G)` | All-pairs path lengths |
| `nx.dijkstra_path(G, source, target, weight)` | Dijkstra's shortest path |
| `nx.dijkstra_path_length(G, source, target)` | Dijkstra path length |
| `nx.bellman_ford_path(G, source, target)` | Bellman-Ford shortest path |
| `nx.floyd_warshall(G, weight)` | Floyd-Warshall all-pairs |
| `nx.astar_path(G, source, target, heuristic)` | A* shortest path |
| `nx.average_shortest_path_length(G)` | Average over all pairs |
| `nx.has_path(G, source, target)` | Path existence check |

---

## Connectivity

| Function | Description |
|----------|-------------|
| `nx.is_connected(G)` | Test connectivity |
| `nx.connected_components(G)` | Iterator over connected components |
| `nx.number_connected_components(G)` | Count components |
| `nx.node_connectivity(G)` | Node connectivity |
| `nx.edge_connectivity(G)` | Edge connectivity |
| `nx.is_strongly_connected(G)` | Strong connectivity (DiGraph) |
| `nx.strongly_connected_components(G)` | Strong components |
| `nx.is_weakly_connected(G)` | Weak connectivity (DiGraph) |
| `nx.weakly_connected_components(G)` | Weak components |
| `nx.is_biconnected(G)` | Biconnectivity test |
| `nx.articulation_points(G)` | Cut vertices |
| `nx.bridges(G)` | Bridge edges |
| `nx.minimum_node_cut(G, s, t)` | Minimum node cut |
| `nx.minimum_edge_cut(G, s, t)` | Minimum edge cut |

---

## Centrality Measures

| Function | Description |
|----------|-------------|
| `nx.degree_centrality(G)` | Degree centrality |
| `nx.in_degree_centrality(G)` | In-degree centrality (DiGraph) |
| `nx.out_degree_centrality(G)` | Out-degree centrality (DiGraph) |
| `nx.betweenness_centrality(G, weight)` | Betweenness centrality |
| `nx.edge_betweenness_centrality(G)` | Edge betweenness |
| `nx.closeness_centrality(G)` | Closeness centrality |
| `nx.eigenvector_centrality(G, max_iter)` | Eigenvector centrality |
| `nx.katz_centrality(G, alpha, beta)` | Katz centrality |
| `nx.pagerank(G, alpha, max_iter)` | PageRank |
| `nx.hits(G, max_iter)` | HITS (hubs and authorities) |
| `nx.harmonic_centrality(G)` | Harmonic centrality |
| `nx.load_centrality(G)` | Load centrality |
| `nx.percolation_centrality(G)` | Percolation centrality |
| `nx.current_flow_betweenness_centrality(G)` | Current-flow betweenness |
| `nx.information_centrality(G)` | Information centrality |

---

## Clustering & Structure

| Function | Description |
|----------|-------------|
| `nx.clustering(G, nodes)` | Clustering coefficient |
| `nx.average_clustering(G)` | Average clustering |
| `nx.transitivity(G)` | Graph transitivity |
| `nx.triangles(G, nodes)` | Number of triangles |
| `nx.square_clustering(G, nodes)` | Square clustering |
| `nx.diameter(G)` | Graph diameter |
| `nx.radius(G)` | Graph radius |
| `nx.eccentricity(G, v)` | Node eccentricity |
| `nx.center(G)` | Center nodes |
| `nx.periphery(G)` | Periphery nodes |
| `nx.density(G)` | Graph density |
| `nx.is_eulerian(G)` | Eulerian check |
| `nx.is_tree(G)` | Tree check |
| `nx.is_forest(G)` | Forest check |
| `nx.is_planar(G)` | Planarity check |
| `nx.is_bipartite(G)` | Bipartiteness check |
| `nx.is_directed_acyclic_graph(G)` | DAG check |
| `nx.degree_histogram(G)` | Degree histogram |
| `nx.degree_assortativity_coefficient(G)` | Assortativity |
| `nx.average_neighbor_degree(G)` | Average neighbor degree |
| `nx.k_core(G, k)` | K-core subgraph |
| `nx.rich_club_coefficient(G)` | Rich club coefficient |
| `nx.cliques.find_cliques(G)` | Enumerate all maximal cliques |
| `nx.cliques.graph_clique_number(G)` | Clique number |

---

## Community Detection

| Function | Description |
|----------|-------------|
| `nx.community.greedy_modularity_communities(G)` | Greedy modularity optimization |
| `nx.community.louvain_communities(G, seed)` | Louvain method |
| `nx.community.label_propagation_communities(G)` | Label propagation |
| `nx.community.asyn_lpa_communities(G)` | Async label propagation |
| `nx.community.girvan_newman(G)` | Girvan-Newman hierarchical |
| `nx.community.kernighan_lin_bisection(G)` | Kernighan-Lin bisection |
| `nx.community.modularity(G, communities)` | Compute modularity score |

---

## Spanning Trees & Flows

| Function | Description |
|----------|-------------|
| `nx.minimum_spanning_tree(G, weight)` | MST (Kruskal's) |
| `nx.maximum_spanning_tree(G, weight)` | Maximum spanning tree |
| `nx.minimum_spanning_edges(G)` | MST edges iterator |
| `nx.maximum_flow(G, s, t, capacity)` | Maximum flow value and flow dict |
| `nx.maximum_flow_value(G, s, t)` | Maximum flow value only |
| `nx.minimum_cut(G, s, t, capacity)` | Minimum cut value and partition |
| `nx.minimum_cut_value(G, s, t)` | Minimum cut value |
| `nx.cost_of_flow(G, flowDict)` | Cost of a given flow |
| `nx.max_weight_matching(G)` | Maximum weight matching |

---

## Traversal

| Function | Description |
|----------|-------------|
| `nx.bfs_tree(G, source)` | BFS tree |
| `nx.bfs_edges(G, source)` | BFS edge iterator |
| `nx.bfs_layers(G, sources)` | BFS layers |
| `nx.dfs_tree(G, source)` | DFS tree |
| `nx.dfs_edges(G, source)` | DFS edge iterator |
| `nx.dfs_preorder_nodes(G, source)` | DFS preorder |
| `nx.dfs_postorder_nodes(G, source)` | DFS postorder |
| `nx.topological_sort(G)` | Topological ordering (DAG) |
| `nx.topological_generations(G)` | Topological generations |
| `nx.all_topological_sorts(G)` | All topological orderings |
| `nx.ancestors(G, node)` | All ancestors (DiGraph) |
| `nx.descendants(G, node)` | All descendants (DiGraph) |

---

## Graph Operations

| Function | Description |
|----------|-------------|
| `nx.compose(G, H)` | Union of two graphs |
| `nx.union(G, H)` | Disjoint union |
| `nx.disjoint_union(G, H)` | Disjoint union with relabeling |
| `nx.intersection(G, H)` | Edge intersection |
| `nx.difference(G, H)` | Edge difference |
| `nx.symmetric_difference(G, H)` | Symmetric edge difference |
| `nx.cartesian_product(G, H)` | Cartesian product |
| `nx.tensor_product(G, H)` | Tensor product |
| `nx.complement(G)` | Graph complement |
| `nx.reverse(G)` | Reverse directed graph |
| `nx.subgraph(G, nodes)` / `G.subgraph(nodes)` | Induced subgraph |
| `nx.line_graph(G)` | Line graph |
| `nx.power(G, k)` | K-th power of graph |
| `nx.relabel_nodes(G, mapping)` | Relabel nodes |
| `nx.convert_node_labels_to_integers(G)` | Integer node labels |
| `G.to_directed()` | Convert to directed |
| `G.to_undirected()` | Convert to undirected |
| `nx.freeze(G)` | Make graph immutable |

---

## Link Analysis

| Function | Description |
|----------|-------------|
| `nx.pagerank(G, alpha)` | PageRank |
| `nx.hits(G)` | HITS algorithm (hubs, authorities) |
| `nx.simrank_similarity(G)` | SimRank similarity |
| `nx.jaccard_coefficient(G, ebunch)` | Jaccard link prediction |
| `nx.adamic_adar_index(G, ebunch)` | Adamic-Adar link prediction |
| `nx.preferential_attachment(G, ebunch)` | Preferential attachment score |
| `nx.resource_allocation_index(G, ebunch)` | Resource allocation |
| `nx.common_neighbor_centrality(G, ebunch)` | Common neighbor centrality |

---

## Graph Coloring

| Function | Description |
|----------|-------------|
| `nx.coloring.greedy_color(G, strategy)` | Greedy graph coloring |
| `nx.is_chordal(G)` | Chordality check |
| `nx.chromatic_number(G)` | Chromatic number (small graphs) |

Strategies: `largest_first`, `smallest_last`, `independent_set`, `random_sequential`, `DSATUR`

---

## I/O & Conversion

| Function | Description |
|----------|-------------|
| `nx.to_numpy_array(G)` | Adjacency matrix as numpy array |
| `nx.from_numpy_array(A)` | Graph from adjacency matrix |
| `nx.to_dict_of_lists(G)` | Dict of adjacency lists |
| `nx.from_dict_of_lists(d)` | Graph from dict |
| `nx.to_edgelist(G)` | Edge list |
| `nx.from_edgelist(edgelist)` | Graph from edge list |
| `nx.adjacency_matrix(G)` | Sparse adjacency matrix |
| `nx.incidence_matrix(G)` | Incidence matrix |
| `nx.laplacian_matrix(G)` | Laplacian matrix |
| `nx.normalized_laplacian_matrix(G)` | Normalized Laplacian |
| `nx.algebraic_connectivity(G)` | Algebraic connectivity (Fiedler value) |

---

## Not Available

- Visualization (`nx.draw()` requires matplotlib display backend -- use plotly for graph visualization)
- GraphML/GML file I/O (filesystem limited on iOS)
