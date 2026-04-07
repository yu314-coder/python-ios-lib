"""Naive Bayes classifiers: Gaussian, Multinomial, Bernoulli."""
import numpy as np
from sklearn.base import BaseEstimator, ClassifierMixin


class GaussianNB(BaseEstimator, ClassifierMixin):
    def __init__(self, var_smoothing=1e-9):
        self.var_smoothing = var_smoothing
        self.classes_ = None
        self.theta_ = None  # mean per class
        self.var_ = None    # variance per class
        self.class_prior_ = None

    def fit(self, X, y):
        X, y = np.asarray(X, dtype=float), np.asarray(y)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        self.classes_ = np.unique(y)
        n_classes = len(self.classes_)
        n_features = X.shape[1]
        self.theta_ = np.zeros((n_classes, n_features))
        self.var_ = np.zeros((n_classes, n_features))
        self.class_prior_ = np.zeros(n_classes)
        for i, c in enumerate(self.classes_):
            X_c = X[y == c]
            self.theta_[i] = X_c.mean(axis=0)
            self.var_[i] = X_c.var(axis=0) + self.var_smoothing
            self.class_prior_[i] = len(X_c) / len(X)
        return self

    def _log_likelihood(self, X):
        n_classes = len(self.classes_)
        log_prob = np.zeros((len(X), n_classes))
        for i in range(n_classes):
            log_prior = np.log(self.class_prior_[i])
            log_gaussian = -0.5 * np.sum(
                np.log(2 * np.pi * self.var_[i]) +
                (X - self.theta_[i]) ** 2 / self.var_[i],
                axis=1
            )
            log_prob[:, i] = log_prior + log_gaussian
        return log_prob

    def predict(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        log_prob = self._log_likelihood(X)
        return self.classes_[np.argmax(log_prob, axis=1)]

    def predict_proba(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        log_prob = self._log_likelihood(X)
        # Log-sum-exp for numerical stability
        max_log = np.max(log_prob, axis=1, keepdims=True)
        log_prob_shifted = log_prob - max_log
        prob = np.exp(log_prob_shifted)
        prob /= prob.sum(axis=1, keepdims=True)
        return prob


class MultinomialNB(BaseEstimator, ClassifierMixin):
    def __init__(self, alpha=1.0):
        self.alpha = alpha
        self.classes_ = None
        self.feature_log_prob_ = None
        self.class_log_prior_ = None

    def fit(self, X, y):
        X, y = np.asarray(X, dtype=float), np.asarray(y)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        self.classes_ = np.unique(y)
        n_classes = len(self.classes_)
        n_features = X.shape[1]
        self.feature_log_prob_ = np.zeros((n_classes, n_features))
        self.class_log_prior_ = np.zeros(n_classes)
        for i, c in enumerate(self.classes_):
            X_c = X[y == c]
            self.class_log_prior_[i] = np.log(len(X_c) / len(X))
            # Smoothed feature counts
            feature_count = X_c.sum(axis=0) + self.alpha
            total_count = feature_count.sum()
            self.feature_log_prob_[i] = np.log(feature_count / total_count)
        return self

    def predict(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        log_prob = X @ self.feature_log_prob_.T + self.class_log_prior_
        return self.classes_[np.argmax(log_prob, axis=1)]

    def predict_proba(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        log_prob = X @ self.feature_log_prob_.T + self.class_log_prior_
        max_log = np.max(log_prob, axis=1, keepdims=True)
        prob = np.exp(log_prob - max_log)
        prob /= prob.sum(axis=1, keepdims=True)
        return prob


class BernoulliNB(BaseEstimator, ClassifierMixin):
    def __init__(self, alpha=1.0, binarize=0.0):
        self.alpha = alpha
        self.binarize = binarize
        self.classes_ = None
        self.feature_log_prob_ = None
        self.class_log_prior_ = None

    def _binarize(self, X):
        if self.binarize is not None:
            return (X > self.binarize).astype(float)
        return X

    def fit(self, X, y):
        X, y = np.asarray(X, dtype=float), np.asarray(y)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        X = self._binarize(X)
        self.classes_ = np.unique(y)
        n_classes = len(self.classes_)
        n_features = X.shape[1]
        self.feature_log_prob_ = np.zeros((n_classes, n_features))
        self.feature_log_neg_prob_ = np.zeros((n_classes, n_features))
        self.class_log_prior_ = np.zeros(n_classes)
        for i, c in enumerate(self.classes_):
            X_c = X[y == c]
            n_c = len(X_c)
            self.class_log_prior_[i] = np.log(n_c / len(X))
            # Smoothed probability of feature being 1
            p = (X_c.sum(axis=0) + self.alpha) / (n_c + 2 * self.alpha)
            self.feature_log_prob_[i] = np.log(p)
            self.feature_log_neg_prob_[i] = np.log(1 - p)
        return self

    def predict(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        X = self._binarize(X)
        # log P(x|c) = sum(x_j * log(p_j) + (1 - x_j) * log(1 - p_j))
        log_prob = np.zeros((len(X), len(self.classes_)))
        for i in range(len(self.classes_)):
            log_prob[:, i] = (
                self.class_log_prior_[i] +
                X @ self.feature_log_prob_[i] +
                (1 - X) @ self.feature_log_neg_prob_[i]
            )
        return self.classes_[np.argmax(log_prob, axis=1)]

    def predict_proba(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        X = self._binarize(X)
        log_prob = np.zeros((len(X), len(self.classes_)))
        for i in range(len(self.classes_)):
            log_prob[:, i] = (
                self.class_log_prior_[i] +
                X @ self.feature_log_prob_[i] +
                (1 - X) @ self.feature_log_neg_prob_[i]
            )
        max_log = np.max(log_prob, axis=1, keepdims=True)
        prob = np.exp(log_prob - max_log)
        prob /= prob.sum(axis=1, keepdims=True)
        return prob
