"""Decision tree classifier and regressor."""
import numpy as np
from sklearn.base import BaseEstimator, ClassifierMixin, RegressorMixin


class _Node:
    __slots__ = ['feature', 'threshold', 'left', 'right', 'value']
    def __init__(self, feature=None, threshold=None, left=None, right=None, value=None):
        self.feature = feature
        self.threshold = threshold
        self.left = left
        self.right = right
        self.value = value


class DecisionTreeClassifier(BaseEstimator, ClassifierMixin):
    def __init__(self, max_depth=10, min_samples_split=2, criterion='gini'):
        self.max_depth = max_depth
        self.min_samples_split = min_samples_split
        self.criterion = criterion
        self.tree_ = None
        self.classes_ = None
        self.n_features_ = None

    def _gini(self, y):
        _, counts = np.unique(y, return_counts=True)
        p = counts / len(y)
        return 1.0 - np.sum(p ** 2)

    def _best_split(self, X, y):
        best_gain, best_feat, best_thresh = -1, None, None
        current = self._gini(y)
        n = len(y)
        for f in range(X.shape[1]):
            thresholds = np.unique(X[:, f])
            if len(thresholds) > 20:
                thresholds = np.percentile(X[:, f], np.linspace(0, 100, 20))
            for t in thresholds:
                left_mask = X[:, f] <= t
                if left_mask.sum() < 1 or (~left_mask).sum() < 1:
                    continue
                gain = current - (left_mask.sum() / n * self._gini(y[left_mask]) +
                                  (~left_mask).sum() / n * self._gini(y[~left_mask]))
                if gain > best_gain:
                    best_gain, best_feat, best_thresh = gain, f, t
        return best_feat, best_thresh

    def _build(self, X, y, depth):
        if depth >= self.max_depth or len(y) < self.min_samples_split or len(np.unique(y)) == 1:
            vals = np.zeros(len(self.classes_))
            for i, c in enumerate(self.classes_):
                vals[i] = np.sum(y == c)
            return _Node(value=vals)
        feat, thresh = self._best_split(X, y)
        if feat is None:
            vals = np.zeros(len(self.classes_))
            for i, c in enumerate(self.classes_):
                vals[i] = np.sum(y == c)
            return _Node(value=vals)
        left_mask = X[:, feat] <= thresh
        return _Node(feature=feat, threshold=thresh,
                     left=self._build(X[left_mask], y[left_mask], depth + 1),
                     right=self._build(X[~left_mask], y[~left_mask], depth + 1))

    def fit(self, X, y):
        X, y = np.asarray(X, dtype=float), np.asarray(y)
        if X.ndim == 1: X = X.reshape(-1, 1)
        self.classes_ = np.unique(y)
        self.n_features_ = X.shape[1]
        self.tree_ = self._build(X, y, 0)
        return self

    def _predict_one(self, x, node):
        if node.value is not None:
            return self.classes_[np.argmax(node.value)]
        if x[node.feature] <= node.threshold:
            return self._predict_one(x, node.left)
        return self._predict_one(x, node.right)

    def predict(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1: X = X.reshape(-1, 1)
        return np.array([self._predict_one(x, self.tree_) for x in X])


class DecisionTreeRegressor(BaseEstimator, RegressorMixin):
    def __init__(self, max_depth=10, min_samples_split=2):
        self.max_depth = max_depth
        self.min_samples_split = min_samples_split
        self.tree_ = None

    def _build(self, X, y, depth):
        if depth >= self.max_depth or len(y) < self.min_samples_split:
            return _Node(value=np.mean(y))
        best_mse, best_feat, best_thresh = np.inf, None, None
        for f in range(X.shape[1]):
            thresholds = np.unique(X[:, f])
            if len(thresholds) > 20:
                thresholds = np.percentile(X[:, f], np.linspace(0, 100, 20))
            for t in thresholds:
                left_mask = X[:, f] <= t
                if left_mask.sum() < 1 or (~left_mask).sum() < 1:
                    continue
                mse = (np.var(y[left_mask]) * left_mask.sum() + np.var(y[~left_mask]) * (~left_mask).sum())
                if mse < best_mse:
                    best_mse, best_feat, best_thresh = mse, f, t
        if best_feat is None:
            return _Node(value=np.mean(y))
        left_mask = X[:, best_feat] <= best_thresh
        return _Node(feature=best_feat, threshold=best_thresh,
                     left=self._build(X[left_mask], y[left_mask], depth + 1),
                     right=self._build(X[~left_mask], y[~left_mask], depth + 1))

    def fit(self, X, y):
        X, y = np.asarray(X, dtype=float), np.asarray(y, dtype=float)
        if X.ndim == 1: X = X.reshape(-1, 1)
        self.tree_ = self._build(X, y, 0)
        return self

    def _predict_one(self, x, node):
        if node.left is None:
            return node.value
        if x[node.feature] <= node.threshold:
            return self._predict_one(x, node.left)
        return self._predict_one(x, node.right)

    def predict(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1: X = X.reshape(-1, 1)
        return np.array([self._predict_one(x, self.tree_) for x in X])
