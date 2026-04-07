"""Ensemble methods: Random Forest, Gradient Boosting, AdaBoost, Bagging."""
import numpy as np
from sklearn.base import BaseEstimator, ClassifierMixin, RegressorMixin
from sklearn.tree import DecisionTreeClassifier, DecisionTreeRegressor


class RandomForestClassifier(BaseEstimator, ClassifierMixin):
    def __init__(self, n_estimators=100, max_depth=10, min_samples_split=2,
                 max_features='sqrt', random_state=None):
        self.n_estimators = n_estimators
        self.max_depth = max_depth
        self.min_samples_split = min_samples_split
        self.max_features = max_features
        self.random_state = random_state
        self.estimators_ = []
        self.classes_ = None

    def _get_max_features(self, n_features):
        if self.max_features == 'sqrt':
            return max(1, int(np.sqrt(n_features)))
        elif self.max_features == 'log2':
            return max(1, int(np.log2(n_features)))
        elif isinstance(self.max_features, int):
            return self.max_features
        elif isinstance(self.max_features, float):
            return max(1, int(self.max_features * n_features))
        return n_features

    def fit(self, X, y):
        X, y = np.asarray(X, dtype=float), np.asarray(y)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        self.classes_ = np.unique(y)
        rng = np.random.RandomState(self.random_state)
        n_samples, n_features = X.shape
        max_feat = self._get_max_features(n_features)
        self.estimators_ = []
        self.feature_indices_ = []
        for i in range(self.n_estimators):
            idx = rng.randint(0, n_samples, n_samples)
            feat_idx = rng.choice(n_features, max_feat, replace=False)
            feat_idx.sort()
            tree = DecisionTreeClassifier(
                max_depth=self.max_depth,
                min_samples_split=self.min_samples_split
            )
            tree.fit(X[np.ix_(idx, feat_idx)], y[idx])
            self.estimators_.append(tree)
            self.feature_indices_.append(feat_idx)
        return self

    def predict(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        predictions = np.array([
            tree.predict(X[:, feat_idx])
            for tree, feat_idx in zip(self.estimators_, self.feature_indices_)
        ])
        # Majority vote
        result = np.empty(X.shape[0], dtype=self.classes_.dtype)
        for i in range(X.shape[0]):
            vals, counts = np.unique(predictions[:, i], return_counts=True)
            result[i] = vals[np.argmax(counts)]
        return result


class RandomForestRegressor(BaseEstimator, RegressorMixin):
    def __init__(self, n_estimators=100, max_depth=10, min_samples_split=2,
                 max_features='sqrt', random_state=None):
        self.n_estimators = n_estimators
        self.max_depth = max_depth
        self.min_samples_split = min_samples_split
        self.max_features = max_features
        self.random_state = random_state
        self.estimators_ = []

    def _get_max_features(self, n_features):
        if self.max_features == 'sqrt':
            return max(1, int(np.sqrt(n_features)))
        elif self.max_features == 'log2':
            return max(1, int(np.log2(n_features)))
        elif isinstance(self.max_features, int):
            return self.max_features
        elif isinstance(self.max_features, float):
            return max(1, int(self.max_features * n_features))
        return n_features

    def fit(self, X, y):
        X, y = np.asarray(X, dtype=float), np.asarray(y, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        rng = np.random.RandomState(self.random_state)
        n_samples, n_features = X.shape
        max_feat = self._get_max_features(n_features)
        self.estimators_ = []
        self.feature_indices_ = []
        for i in range(self.n_estimators):
            idx = rng.randint(0, n_samples, n_samples)
            feat_idx = rng.choice(n_features, max_feat, replace=False)
            feat_idx.sort()
            tree = DecisionTreeRegressor(
                max_depth=self.max_depth,
                min_samples_split=self.min_samples_split
            )
            tree.fit(X[np.ix_(idx, feat_idx)], y[idx])
            self.estimators_.append(tree)
            self.feature_indices_.append(feat_idx)
        return self

    def predict(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        predictions = np.array([
            tree.predict(X[:, feat_idx])
            for tree, feat_idx in zip(self.estimators_, self.feature_indices_)
        ])
        return np.mean(predictions, axis=0)


class GradientBoostingClassifier(BaseEstimator, ClassifierMixin):
    """Binary and multiclass gradient boosting classifier using log-loss."""

    def __init__(self, n_estimators=100, learning_rate=0.1, max_depth=3,
                 min_samples_split=2, random_state=None):
        self.n_estimators = n_estimators
        self.learning_rate = learning_rate
        self.max_depth = max_depth
        self.min_samples_split = min_samples_split
        self.random_state = random_state
        self.estimators_ = []
        self.classes_ = None

    @staticmethod
    def _sigmoid(x):
        x = np.clip(x, -500, 500)
        return 1.0 / (1.0 + np.exp(-x))

    @staticmethod
    def _softmax(x):
        x = x - np.max(x, axis=1, keepdims=True)
        e = np.exp(x)
        return e / e.sum(axis=1, keepdims=True)

    def fit(self, X, y):
        X, y = np.asarray(X, dtype=float), np.asarray(y)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        self.classes_ = np.unique(y)
        n_classes = len(self.classes_)

        if n_classes == 2:
            # Binary: single output
            y_bin = (y == self.classes_[1]).astype(float)
            p = np.mean(y_bin)
            self.init_pred_ = np.log(max(p, 1e-15) / max(1 - p, 1e-15))
            F = np.full(len(X), self.init_pred_)
            self.estimators_ = []
            for _ in range(self.n_estimators):
                prob = self._sigmoid(F)
                residual = y_bin - prob
                tree = DecisionTreeRegressor(
                    max_depth=self.max_depth,
                    min_samples_split=self.min_samples_split
                )
                tree.fit(X, residual)
                F += self.learning_rate * tree.predict(X)
                self.estimators_.append(tree)
        else:
            # Multiclass: one tree per class per iteration
            label_matrix = np.zeros((len(y), n_classes))
            for k, c in enumerate(self.classes_):
                label_matrix[:, k] = (y == c).astype(float)
            prior = label_matrix.mean(axis=0)
            prior = np.clip(prior, 1e-15, 1 - 1e-15)
            self.init_pred_ = np.log(prior)
            F = np.tile(self.init_pred_, (len(X), 1))
            self.estimators_ = []
            for _ in range(self.n_estimators):
                prob = self._softmax(F)
                trees_round = []
                for k in range(n_classes):
                    residual = label_matrix[:, k] - prob[:, k]
                    tree = DecisionTreeRegressor(
                        max_depth=self.max_depth,
                        min_samples_split=self.min_samples_split
                    )
                    tree.fit(X, residual)
                    F[:, k] += self.learning_rate * tree.predict(X)
                    trees_round.append(tree)
                self.estimators_.append(trees_round)
        return self

    def predict(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        n_classes = len(self.classes_)
        if n_classes == 2:
            F = np.full(len(X), self.init_pred_)
            for tree in self.estimators_:
                F += self.learning_rate * tree.predict(X)
            prob = self._sigmoid(F)
            indices = (prob >= 0.5).astype(int)
            return self.classes_[indices]
        else:
            F = np.tile(self.init_pred_, (len(X), 1))
            for trees_round in self.estimators_:
                for k, tree in enumerate(trees_round):
                    F[:, k] += self.learning_rate * tree.predict(X)
            return self.classes_[np.argmax(F, axis=1)]


class GradientBoostingRegressor(BaseEstimator, RegressorMixin):
    def __init__(self, n_estimators=100, learning_rate=0.1, max_depth=3,
                 min_samples_split=2, random_state=None):
        self.n_estimators = n_estimators
        self.learning_rate = learning_rate
        self.max_depth = max_depth
        self.min_samples_split = min_samples_split
        self.random_state = random_state
        self.estimators_ = []
        self.init_pred_ = None

    def fit(self, X, y):
        X, y = np.asarray(X, dtype=float), np.asarray(y, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        self.init_pred_ = np.mean(y)
        F = np.full(len(X), self.init_pred_)
        self.estimators_ = []
        for _ in range(self.n_estimators):
            residual = y - F
            tree = DecisionTreeRegressor(
                max_depth=self.max_depth,
                min_samples_split=self.min_samples_split
            )
            tree.fit(X, residual)
            F += self.learning_rate * tree.predict(X)
            self.estimators_.append(tree)
        return self

    def predict(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        F = np.full(len(X), self.init_pred_)
        for tree in self.estimators_:
            F += self.learning_rate * tree.predict(X)
        return F


class AdaBoostClassifier(BaseEstimator, ClassifierMixin):
    def __init__(self, n_estimators=50, learning_rate=1.0, random_state=None):
        self.n_estimators = n_estimators
        self.learning_rate = learning_rate
        self.random_state = random_state
        self.estimators_ = []
        self.estimator_weights_ = []
        self.classes_ = None

    def fit(self, X, y):
        X, y = np.asarray(X, dtype=float), np.asarray(y)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        self.classes_ = np.unique(y)
        n_samples = len(X)
        w = np.full(n_samples, 1.0 / n_samples)
        self.estimators_ = []
        self.estimator_weights_ = []
        rng = np.random.RandomState(self.random_state)
        for _ in range(self.n_estimators):
            tree = DecisionTreeClassifier(max_depth=1, min_samples_split=2)
            # Weighted bootstrap sample
            indices = rng.choice(n_samples, n_samples, replace=True, p=w)
            tree.fit(X[indices], y[indices])
            pred = tree.predict(X)
            incorrect = (pred != y)
            err = np.sum(w * incorrect) / np.sum(w)
            err = np.clip(err, 1e-15, 1 - 1e-15)
            if err >= 0.5:
                break
            alpha = self.learning_rate * 0.5 * np.log((1 - err) / err)
            w *= np.exp(alpha * incorrect.astype(float) * 2 - alpha)
            w /= np.sum(w)
            self.estimators_.append(tree)
            self.estimator_weights_.append(alpha)
        return self

    def predict(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        if len(self.estimators_) == 0:
            return np.full(len(X), self.classes_[0])
        # Weighted vote
        n_classes = len(self.classes_)
        class_votes = np.zeros((len(X), n_classes))
        for tree, alpha in zip(self.estimators_, self.estimator_weights_):
            pred = tree.predict(X)
            for k, c in enumerate(self.classes_):
                class_votes[:, k] += alpha * (pred == c)
        return self.classes_[np.argmax(class_votes, axis=1)]


class BaggingClassifier(BaseEstimator, ClassifierMixin):
    def __init__(self, base_estimator=None, n_estimators=10, max_samples=1.0,
                 random_state=None):
        self.base_estimator = base_estimator
        self.n_estimators = n_estimators
        self.max_samples = max_samples
        self.random_state = random_state
        self.estimators_ = []
        self.classes_ = None

    def fit(self, X, y):
        X, y = np.asarray(X, dtype=float), np.asarray(y)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        self.classes_ = np.unique(y)
        rng = np.random.RandomState(self.random_state)
        n_samples = X.shape[0]
        if isinstance(self.max_samples, float):
            sample_size = max(1, int(self.max_samples * n_samples))
        else:
            sample_size = self.max_samples
        self.estimators_ = []
        for _ in range(self.n_estimators):
            idx = rng.randint(0, n_samples, sample_size)
            if self.base_estimator is not None:
                est = type(self.base_estimator)(**self.base_estimator.get_params())
            else:
                est = DecisionTreeClassifier(max_depth=10)
            est.fit(X[idx], y[idx])
            self.estimators_.append(est)
        return self

    def predict(self, X):
        X = np.asarray(X, dtype=float)
        if X.ndim == 1:
            X = X.reshape(-1, 1)
        predictions = np.array([est.predict(X) for est in self.estimators_])
        result = np.empty(X.shape[0], dtype=self.classes_.dtype)
        for i in range(X.shape[0]):
            vals, counts = np.unique(predictions[:, i], return_counts=True)
            result[i] = vals[np.argmax(counts)]
        return result
