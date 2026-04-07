"""SVM via simplified gradient descent (linear kernel)."""
import numpy as np
from sklearn.base import BaseEstimator, ClassifierMixin


class SVC(BaseEstimator, ClassifierMixin):
    """Linear SVM classifier via SGD on hinge loss."""
    def __init__(self, C=1.0, kernel='linear', max_iter=1000, lr=0.001, random_state=None):
        self.C = C
        self.kernel = kernel
        self.max_iter = max_iter
        self.lr = lr
        self.random_state = random_state
        self.classes_ = None
        self.coef_ = None
        self.intercept_ = None

    def fit(self, X, y):
        X = np.asarray(X, dtype=float)
        y = np.asarray(y)
        if X.ndim == 1: X = X.reshape(-1, 1)
        self.classes_ = np.unique(y)
        n, p = X.shape
        if len(self.classes_) == 2:
            y_bin = np.where(y == self.classes_[1], 1.0, -1.0)
            w = np.zeros(p)
            b = 0.0
            rng = np.random.RandomState(self.random_state)
            for t in range(1, self.max_iter + 1):
                i = rng.randint(n)
                margin = y_bin[i] * (X[i] @ w + b)
                eta = self.lr / (1 + self.lr * t * 0.001)
                if margin < 1:
                    w = (1 - eta / self.C) * w + eta * y_bin[i] * X[i]
                    b += eta * y_bin[i]
                else:
                    w = (1 - eta / self.C) * w
            self.coef_ = w.reshape(1, -1)
            self.intercept_ = np.array([b])
        return self

    def predict(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1: X = X.reshape(-1, 1)
        scores = X @ self.coef_[0] + self.intercept_[0]
        return np.where(scores >= 0, self.classes_[1], self.classes_[0])


class SVR(BaseEstimator):
    """Linear SVR (epsilon-insensitive loss)."""
    def __init__(self, C=1.0, epsilon=0.1, max_iter=1000, lr=0.001):
        self.C = C
        self.epsilon = epsilon
        self.max_iter = max_iter
        self.lr = lr
        self.coef_ = None
        self.intercept_ = 0.0

    def fit(self, X, y):
        X = np.asarray(X, dtype=float)
        y = np.asarray(y, dtype=float)
        if X.ndim == 1: X = X.reshape(-1, 1)
        n, p = X.shape
        w = np.zeros(p)
        b = 0.0
        for t in range(1, self.max_iter + 1):
            i = t % n
            pred = X[i] @ w + b
            err = y[i] - pred
            eta = self.lr / (1 + self.lr * t * 0.001)
            if abs(err) > self.epsilon:
                grad = -np.sign(err)
                w -= eta * (grad * X[i] + w / (self.C * n))
                b -= eta * grad
            else:
                w *= (1 - eta / (self.C * n))
        self.coef_ = w
        self.intercept_ = b
        return self

    def predict(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1: X = X.reshape(-1, 1)
        return X @ self.coef_ + self.intercept_
