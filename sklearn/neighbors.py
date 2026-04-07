"""K-Nearest Neighbors."""
import numpy as np
from sklearn.base import BaseEstimator, ClassifierMixin, RegressorMixin


class KNeighborsClassifier(BaseEstimator, ClassifierMixin):
    def __init__(self, n_neighbors=5, weights='uniform', metric='euclidean'):
        self.n_neighbors = n_neighbors
        self.weights = weights
        self.metric = metric
        self.classes_ = None

    def fit(self, X, y):
        self._X = np.asarray(X, dtype=float)
        self._y = np.asarray(y)
        if self._X.ndim == 1: self._X = self._X.reshape(-1, 1)
        self.classes_ = np.unique(y)
        return self

    def predict(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1: X = X.reshape(-1, 1)
        preds = []
        for x in X:
            dists = np.sqrt(np.sum((self._X - x) ** 2, axis=1))
            idx = np.argsort(dists)[:self.n_neighbors]
            if self.weights == 'distance':
                w = 1.0 / np.maximum(dists[idx], 1e-10)
                counts = {}
                for i, wi in zip(idx, w):
                    c = self._y[i]
                    counts[c] = counts.get(c, 0) + wi
                preds.append(max(counts, key=counts.get))
            else:
                vals, counts = np.unique(self._y[idx], return_counts=True)
                preds.append(vals[np.argmax(counts)])
        return np.array(preds)


class KNeighborsRegressor(BaseEstimator, RegressorMixin):
    def __init__(self, n_neighbors=5, weights='uniform'):
        self.n_neighbors = n_neighbors
        self.weights = weights

    def fit(self, X, y):
        self._X = np.asarray(X, dtype=float)
        self._y = np.asarray(y, dtype=float)
        if self._X.ndim == 1: self._X = self._X.reshape(-1, 1)
        return self

    def predict(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1: X = X.reshape(-1, 1)
        preds = []
        for x in X:
            dists = np.sqrt(np.sum((self._X - x) ** 2, axis=1))
            idx = np.argsort(dists)[:self.n_neighbors]
            if self.weights == 'distance':
                w = 1.0 / np.maximum(dists[idx], 1e-10)
                preds.append(np.average(self._y[idx], weights=w))
            else:
                preds.append(np.mean(self._y[idx]))
        return np.array(preds)
