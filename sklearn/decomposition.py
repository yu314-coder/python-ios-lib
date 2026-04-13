"""Decomposition: PCA, TruncatedSVD."""
import numpy as np
from sklearn.base import BaseEstimator, TransformerMixin


class PCA(BaseEstimator, TransformerMixin):
    def __init__(self, n_components=None):
        self.n_components = n_components
        self.components_ = None
        self.explained_variance_ = None
        self.explained_variance_ratio_ = None
        self.mean_ = None

    def fit(self, X, y=None):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        n_samples, n_features = X.shape
        self.mean_ = np.mean(X, axis=0)
        X_centered = X - self.mean_
        # Covariance matrix
        cov = np.dot(X_centered.T, X_centered) / (n_samples - 1)
        # Eigendecomposition (eigh returns sorted ascending)
        eigenvalues, eigenvectors = np.linalg.eigh(cov)
        # Sort descending
        idx = np.argsort(eigenvalues)[::-1]
        eigenvalues = eigenvalues[idx]
        eigenvectors = eigenvectors[:, idx]
        # Select components
        n_comp = self.n_components if self.n_components is not None else n_features
        n_comp = min(n_comp, n_features)
        self.components_ = eigenvectors[:, :n_comp].T  # shape (n_components, n_features)
        self.explained_variance_ = eigenvalues[:n_comp]
        total_var = np.sum(eigenvalues)
        self.explained_variance_ratio_ = eigenvalues[:n_comp] / max(total_var, 1e-15)
        return self

    def transform(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        return np.dot(X - self.mean_, self.components_.T)

    def inverse_transform(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1:
            X = X.reshape(1, -1)
        return np.dot(X, self.components_) + self.mean_


class TruncatedSVD(BaseEstimator, TransformerMixin):
    def __init__(self, n_components=2):
        self.n_components = n_components
        self.components_ = None
        self.explained_variance_ = None
        self.explained_variance_ratio_ = None
        self.singular_values_ = None

    def fit(self, X, y=None):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        U, s, Vt = np.linalg.svd(X, full_matrices=False)
        n_comp = min(self.n_components, len(s))
        self.components_ = Vt[:n_comp]
        self.singular_values_ = s[:n_comp]
        self.explained_variance_ = (s[:n_comp] ** 2) / (X.shape[0] - 1)
        total_var = np.sum(s ** 2) / (X.shape[0] - 1)
        self.explained_variance_ratio_ = self.explained_variance_ / max(total_var, 1e-15)
        return self

    def transform(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        return np.dot(X, self.components_.T)

    def inverse_transform(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1:
            X = X.reshape(1, -1)
        return np.dot(X, self.components_)
