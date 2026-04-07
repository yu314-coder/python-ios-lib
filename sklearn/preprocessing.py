"""Preprocessing: StandardScaler, MinMaxScaler, LabelEncoder, OneHotEncoder, PolynomialFeatures, RobustScaler."""
import numpy as np
from sklearn.base import BaseEstimator, TransformerMixin


class StandardScaler(BaseEstimator, TransformerMixin):
    def __init__(self, with_mean=True, with_std=True):
        self.with_mean = with_mean
        self.with_std = with_std
        self.mean_ = None
        self.scale_ = None

    def fit(self, X, y=None):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1: X = X.reshape(-1, 1)
        self.mean_ = np.mean(X, axis=0) if self.with_mean else np.zeros(X.shape[1])
        self.scale_ = np.std(X, axis=0) if self.with_std else np.ones(X.shape[1])
        self.scale_[self.scale_ == 0] = 1.0
        return self

    def transform(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1: X = X.reshape(-1, 1)
        return (X - self.mean_) / self.scale_

    def inverse_transform(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1: X = X.reshape(-1, 1)
        return X * self.scale_ + self.mean_


class MinMaxScaler(BaseEstimator, TransformerMixin):
    def __init__(self, feature_range=(0, 1)):
        self.feature_range = feature_range
        self.min_ = None
        self.scale_ = None
        self.data_min_ = None
        self.data_max_ = None

    def fit(self, X, y=None):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1: X = X.reshape(-1, 1)
        self.data_min_ = np.min(X, axis=0)
        self.data_max_ = np.max(X, axis=0)
        rng = self.data_max_ - self.data_min_
        rng[rng == 0] = 1.0
        self.scale_ = (self.feature_range[1] - self.feature_range[0]) / rng
        self.min_ = self.feature_range[0] - self.data_min_ * self.scale_
        return self

    def transform(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1: X = X.reshape(-1, 1)
        return X * self.scale_ + self.min_

    def inverse_transform(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1: X = X.reshape(-1, 1)
        return (X - self.min_) / self.scale_


class LabelEncoder(BaseEstimator):
    def __init__(self):
        self.classes_ = None

    def fit(self, y):
        self.classes_ = np.unique(y)
        return self

    def transform(self, y):
        y = np.asarray(y)
        mapping = {c: i for i, c in enumerate(self.classes_)}
        return np.array([mapping[v] for v in y])

    def fit_transform(self, y):
        return self.fit(y).transform(y)

    def inverse_transform(self, y):
        return np.array([self.classes_[i] for i in y])


class PolynomialFeatures(BaseEstimator, TransformerMixin):
    def __init__(self, degree=2, include_bias=True):
        self.degree = degree
        self.include_bias = include_bias

    def fit(self, X, y=None):
        return self

    def transform(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1: X = X.reshape(-1, 1)
        n, p = X.shape
        features = [np.ones((n, 1))] if self.include_bias else []
        for d in range(1, self.degree + 1):
            for j in range(p):
                features.append(X[:, j:j+1] ** d)
        # Cross terms for degree 2
        if self.degree >= 2 and p > 1:
            for i in range(p):
                for j in range(i + 1, p):
                    features.append((X[:, i] * X[:, j]).reshape(-1, 1))
        return np.hstack(features)


class OneHotEncoder(BaseEstimator, TransformerMixin):
    def __init__(self, sparse=False, handle_unknown='error'):
        self.sparse = sparse  # always dense in this implementation
        self.handle_unknown = handle_unknown
        self.categories_ = None

    def fit(self, X, y=None):
        X = np.asarray(X)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        self.categories_ = []
        for col in range(X.shape[1]):
            self.categories_.append(np.unique(X[:, col]))
        return self

    def transform(self, X):
        X = np.asarray(X)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        n_samples = X.shape[0]
        encoded_cols = []
        for col in range(X.shape[1]):
            cats = self.categories_[col]
            col_encoded = np.zeros((n_samples, len(cats)), dtype=float)
            for i, cat in enumerate(cats):
                col_encoded[:, i] = (X[:, col] == cat).astype(float)
            if self.handle_unknown == 'ignore':
                pass  # unknown categories get all zeros
            encoded_cols.append(col_encoded)
        return np.hstack(encoded_cols)

    def inverse_transform(self, X):
        X = np.asarray(X, dtype=float)
        n_samples = X.shape[0]
        n_features = len(self.categories_)
        result = np.empty((n_samples, n_features), dtype=object)
        col_offset = 0
        for feat_idx in range(n_features):
            n_cats = len(self.categories_[feat_idx])
            sub = X[:, col_offset:col_offset + n_cats]
            indices = np.argmax(sub, axis=1)
            result[:, feat_idx] = self.categories_[feat_idx][indices]
            col_offset += n_cats
        return result


class RobustScaler(BaseEstimator, TransformerMixin):
    def __init__(self, with_centering=True, with_scaling=True,
                 quantile_range=(25.0, 75.0)):
        self.with_centering = with_centering
        self.with_scaling = with_scaling
        self.quantile_range = quantile_range
        self.center_ = None
        self.scale_ = None

    def fit(self, X, y=None):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        if self.with_centering:
            self.center_ = np.median(X, axis=0)
        else:
            self.center_ = np.zeros(X.shape[1])
        if self.with_scaling:
            q_low, q_high = self.quantile_range
            low = np.percentile(X, q_low, axis=0)
            high = np.percentile(X, q_high, axis=0)
            self.scale_ = high - low
            self.scale_[self.scale_ == 0] = 1.0
        else:
            self.scale_ = np.ones(X.shape[1])
        return self

    def transform(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        return (X - self.center_) / self.scale_

    def inverse_transform(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        return X * self.scale_ + self.center_
