"""Clustering: KMeans, DBSCAN."""
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
