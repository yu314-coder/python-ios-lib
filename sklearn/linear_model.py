"""Linear models: LinearRegression, LogisticRegression, Ridge, Lasso."""
import numpy as np
from sklearn.base import BaseEstimator, RegressorMixin, ClassifierMixin


class LinearRegression(BaseEstimator, RegressorMixin):
    def __init__(self, fit_intercept=True):
        self.fit_intercept = fit_intercept
        self.coef_ = None
        self.intercept_ = 0.0

    def fit(self, X, y):
        X = np.asarray(X, dtype=float)
        y = np.asarray(y, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        if self.fit_intercept:
            X = np.column_stack([np.ones(X.shape[0]), X])
        w = np.linalg.lstsq(X, y, rcond=None)[0]
        if self.fit_intercept:
            self.intercept_ = float(w[0])
            self.coef_ = w[1:]
        else:
            self.coef_ = w
        return self

    def predict(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        return X @ self.coef_ + self.intercept_


class Ridge(BaseEstimator, RegressorMixin):
    def __init__(self, alpha=1.0, fit_intercept=True):
        self.alpha = alpha
        self.fit_intercept = fit_intercept
        self.coef_ = None
        self.intercept_ = 0.0

    def fit(self, X, y):
        X = np.asarray(X, dtype=float)
        y = np.asarray(y, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        if self.fit_intercept:
            self.intercept_ = float(np.mean(y))
            y = y - self.intercept_
        n_features = X.shape[1]
        self.coef_ = np.linalg.solve(X.T @ X + self.alpha * np.eye(n_features), X.T @ y)
        return self

    def predict(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        return X @ self.coef_ + self.intercept_


class Lasso(BaseEstimator, RegressorMixin):
    """Lasso via coordinate descent."""
    def __init__(self, alpha=1.0, fit_intercept=True, max_iter=1000, tol=1e-4):
        self.alpha = alpha
        self.fit_intercept = fit_intercept
        self.max_iter = max_iter
        self.tol = tol
        self.coef_ = None
        self.intercept_ = 0.0

    def fit(self, X, y):
        X = np.asarray(X, dtype=float)
        y = np.asarray(y, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        n, p = X.shape
        if self.fit_intercept:
            self.intercept_ = float(np.mean(y))
            y = y - self.intercept_
        w = np.zeros(p)
        for _ in range(self.max_iter):
            w_old = w.copy()
            for j in range(p):
                r = y - X @ w + X[:, j] * w[j]
                rho = X[:, j] @ r
                z = X[:, j] @ X[:, j]
                if z == 0:
                    w[j] = 0
                else:
                    w[j] = np.sign(rho) * max(abs(rho) - self.alpha * n / 2, 0) / z
            if np.max(np.abs(w - w_old)) < self.tol:
                break
        self.coef_ = w
        return self

    def predict(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        return X @ self.coef_ + self.intercept_


class LogisticRegression(BaseEstimator, ClassifierMixin):
    """Binary/multiclass logistic regression via gradient descent."""
    def __init__(self, C=1.0, max_iter=200, lr=0.1, fit_intercept=True):
        self.C = C
        self.max_iter = max_iter
        self.lr = lr
        self.fit_intercept = fit_intercept
        self.coef_ = None
        self.intercept_ = None
        self.classes_ = None

    def _sigmoid(self, z):
        return 1.0 / (1.0 + np.exp(-np.clip(z, -500, 500)))

    def fit(self, X, y):
        X = np.asarray(X, dtype=float)
        y = np.asarray(y)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        self.classes_ = np.unique(y)
        n, p = X.shape
        if len(self.classes_) == 2:
            y_bin = (y == self.classes_[1]).astype(float)
            w = np.zeros(p)
            b = 0.0
            for _ in range(self.max_iter):
                z = X @ w + b
                h = self._sigmoid(z)
                grad_w = (X.T @ (h - y_bin)) / n + w / (self.C * n)
                grad_b = np.mean(h - y_bin)
                w -= self.lr * grad_w
                b -= self.lr * grad_b
            self.coef_ = w.reshape(1, -1)
            self.intercept_ = np.array([b])
        else:
            k = len(self.classes_)
            W = np.zeros((k, p))
            B = np.zeros(k)
            for _ in range(self.max_iter):
                scores = X @ W.T + B
                exp_s = np.exp(scores - np.max(scores, axis=1, keepdims=True))
                probs = exp_s / exp_s.sum(axis=1, keepdims=True)
                for c in range(k):
                    y_c = (y == self.classes_[c]).astype(float)
                    diff = probs[:, c] - y_c
                    W[c] -= self.lr * (X.T @ diff / n + W[c] / (self.C * n))
                    B[c] -= self.lr * np.mean(diff)
            self.coef_ = W
            self.intercept_ = B
        return self

    def predict(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        if len(self.classes_) == 2:
            proba = self._sigmoid(X @ self.coef_[0] + self.intercept_[0])
            return np.where(proba >= 0.5, self.classes_[1], self.classes_[0])
        scores = X @ self.coef_.T + self.intercept_
        return self.classes_[np.argmax(scores, axis=1)]

    def predict_proba(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        if len(self.classes_) == 2:
            p1 = self._sigmoid(X @ self.coef_[0] + self.intercept_[0])
            return np.column_stack([1 - p1, p1])
        scores = X @ self.coef_.T + self.intercept_
        exp_s = np.exp(scores - np.max(scores, axis=1, keepdims=True))
        return exp_s / exp_s.sum(axis=1, keepdims=True)
