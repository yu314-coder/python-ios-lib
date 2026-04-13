"""Clustering: KMeans, DBSCAN, AgglomerativeClustering."""
import numpy as np
from sklearn.base import BaseEstimator


class KMeans(BaseEstimator):
    def __init__(self, n_clusters=8, max_iter=300, n_init=10, tol=1e-4, random_state=None):
        self.n_clusters = n_clusters
        self.max_iter = max_iter
        self.n_init = n_init
        self.tol = tol
        self.random_state = random_state
        self.cluster_centers_ = None
        self.labels_ = None
        self.inertia_ = None

    def fit(self, X, y=None):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1: X = X.reshape(-1, 1)
        rng = np.random.RandomState(self.random_state)
        best_inertia = np.inf
        for _ in range(self.n_init):
            idx = rng.choice(X.shape[0], self.n_clusters, replace=False)
            centers = X[idx].copy()
            for _ in range(self.max_iter):
                dists = np.sqrt(((X[:, None] - centers[None]) ** 2).sum(axis=2))
                labels = np.argmin(dists, axis=1)
                new_centers = np.array([X[labels == k].mean(axis=0) if np.any(labels == k) else centers[k]
                                        for k in range(self.n_clusters)])
                if np.max(np.abs(new_centers - centers)) < self.tol:
                    centers = new_centers
                    break
                centers = new_centers
            inertia = sum(np.sum((X[labels == k] - centers[k]) ** 2) for k in range(self.n_clusters))
            if inertia < best_inertia:
                best_inertia = inertia
                self.cluster_centers_ = centers
                self.labels_ = labels
                self.inertia_ = inertia
        return self

    def predict(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1: X = X.reshape(-1, 1)
        dists = np.sqrt(((X[:, None] - self.cluster_centers_[None]) ** 2).sum(axis=2))
        return np.argmin(dists, axis=1)

    def fit_predict(self, X, y=None):
        self.fit(X)
        return self.labels_


class DBSCAN(BaseEstimator):
    def __init__(self, eps=0.5, min_samples=5):
        self.eps = eps
        self.min_samples = min_samples
        self.labels_ = None
        self.core_sample_indices_ = None

    def fit(self, X, y=None):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        n = len(X)
        # Compute pairwise distances
        dists = np.sqrt(((X[:, None] - X[None]) ** 2).sum(axis=2))
        # Find neighbors within eps for each point
        neighborhoods = [np.where(dists[i] <= self.eps)[0] for i in range(n)]
        # Identify core points
        core_mask = np.array([len(nb) >= self.min_samples for nb in neighborhoods])
        self.core_sample_indices_ = np.where(core_mask)[0]
        labels = np.full(n, -1, dtype=int)
        cluster_id = 0
        for i in range(n):
            if not core_mask[i] or labels[i] != -1:
                continue
            # BFS to expand cluster
            queue = [i]
            labels[i] = cluster_id
            head = 0
            while head < len(queue):
                point = queue[head]
                head += 1
                if core_mask[point]:
                    for nb in neighborhoods[point]:
                        if labels[nb] == -1:
                            labels[nb] = cluster_id
                            queue.append(nb)
            cluster_id += 1
        self.labels_ = labels
        return self

    def fit_predict(self, X, y=None):
        self.fit(X)
        return self.labels_


class AgglomerativeClustering(BaseEstimator):
    def __init__(self, n_clusters=2, linkage='single'):
        self.n_clusters = n_clusters
        self.linkage = linkage
        self.labels_ = None

    def fit(self, X, y=None):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        n = len(X)
        # Pairwise distance matrix
        dists = np.sqrt(((X[:, None] - X[None]) ** 2).sum(axis=2))
        # Each point starts as its own cluster
        clusters = {i: [i] for i in range(n)}
        # Set diagonal to inf
        np.fill_diagonal(dists, np.inf)
        # Merge until n_clusters remain
        active = set(range(n))
        while len(active) > self.n_clusters:
            # Find closest pair among active clusters
            min_dist = np.inf
            merge_a, merge_b = -1, -1
            active_list = sorted(active)
            for idx_i in range(len(active_list)):
                for idx_j in range(idx_i + 1, len(active_list)):
                    ci, cj = active_list[idx_i], active_list[idx_j]
                    d = dists[ci, cj]
                    if d < min_dist:
                        min_dist = d
                        merge_a, merge_b = ci, cj
            # Merge b into a
            clusters[merge_a].extend(clusters[merge_b])
            del clusters[merge_b]
            active.remove(merge_b)
            # Update distances
            for other in active:
                if other == merge_a:
                    continue
                if self.linkage == 'single':
                    new_dist = min(dists[merge_a, other], dists[merge_b, other])
                elif self.linkage == 'complete':
                    new_dist = max(dists[merge_a, other], dists[merge_b, other])
                else:  # average
                    na = len(clusters[merge_a]) - len(clusters.get(merge_b, []))
                    nb = len(clusters.get(merge_b, [0]))
                    # Weighted average of old distances
                    new_dist = (dists[merge_a, other] + dists[merge_b, other]) / 2
                dists[merge_a, other] = new_dist
                dists[other, merge_a] = new_dist
        # Assign labels
        self.labels_ = np.zeros(n, dtype=int)
        for label, (_, members) in enumerate(sorted(clusters.items())):
            for m in members:
                self.labels_[m] = label
        return self

    def fit_predict(self, X, y=None):
        self.fit(X)
        return self.labels_
