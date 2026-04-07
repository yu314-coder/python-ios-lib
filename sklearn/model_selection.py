"""Model selection: train_test_split, cross_val_score."""
import numpy as np


def train_test_split(*arrays, test_size=0.25, random_state=None, shuffle=True):
    n = len(arrays[0])
    rng = np.random.RandomState(random_state)
    indices = np.arange(n)
    if shuffle:
        rng.shuffle(indices)
    if isinstance(test_size, float):
        split = int(n * (1 - test_size))
    else:
        split = n - test_size
    train_idx, test_idx = indices[:split], indices[split:]
    result = []
    for arr in arrays:
        arr = np.asarray(arr)
        result.append(arr[train_idx])
        result.append(arr[test_idx])
    return result


def cross_val_score(estimator, X, y, cv=5, scoring=None):
    X, y = np.asarray(X), np.asarray(y)
    n = len(X)
    fold_size = n // cv
    scores = []
    indices = np.arange(n)
    for i in range(cv):
        test_idx = indices[i * fold_size:(i + 1) * fold_size] if i < cv - 1 else indices[i * fold_size:]
        train_idx = np.setdiff1d(indices, test_idx)
        est = type(estimator)(**estimator.get_params())
        est.fit(X[train_idx], y[train_idx])
        scores.append(est.score(X[test_idx], y[test_idx]))
    return np.array(scores)


class StratifiedKFold:
    def __init__(self, n_splits=5, shuffle=False, random_state=None):
        self.n_splits = n_splits
        self.shuffle = shuffle
        self.random_state = random_state

    def split(self, X, y):
        X, y = np.asarray(X), np.asarray(y)
        n = len(y)
        rng = np.random.RandomState(self.random_state)
        classes = np.unique(y)
        # Group indices by class
        class_indices = {}
        for c in classes:
            idx = np.where(y == c)[0]
            if self.shuffle:
                rng.shuffle(idx)
            class_indices[c] = idx
        # Distribute into folds
        folds = [[] for _ in range(self.n_splits)]
        for c in classes:
            idx = class_indices[c]
            fold_sizes = np.full(self.n_splits, len(idx) // self.n_splits, dtype=int)
            fold_sizes[:len(idx) % self.n_splits] += 1
            pos = 0
            for fold_idx, size in enumerate(fold_sizes):
                folds[fold_idx].extend(idx[pos:pos + size].tolist())
                pos += size
        for fold_idx in range(self.n_splits):
            test_idx = np.array(folds[fold_idx], dtype=int)
            train_idx = np.array([i for i in range(n) if i not in set(folds[fold_idx])], dtype=int)
            yield train_idx, test_idx

    def get_n_splits(self, X=None, y=None):
        return self.n_splits


class GridSearchCV:
    def __init__(self, estimator, param_grid, cv=5, scoring=None):
        self.estimator = estimator
        self.param_grid = param_grid
        self.cv = cv
        self.scoring = scoring
        self.best_params_ = None
        self.best_score_ = None
        self.best_estimator_ = None
        self.cv_results_ = None

    def _param_combinations(self):
        keys = list(self.param_grid.keys())
        if not keys:
            return [{}]
        values = [self.param_grid[k] for k in keys]
        combos = [{}]
        for key, vals in zip(keys, values):
            new_combos = []
            for combo in combos:
                for v in vals:
                    c = dict(combo)
                    c[key] = v
                    new_combos.append(c)
            combos = new_combos
        return combos

    def fit(self, X, y):
        X, y = np.asarray(X), np.asarray(y)
        combos = self._param_combinations()
        best_score = -np.inf
        results = {'params': [], 'mean_test_score': []}
        for params in combos:
            scores = cross_val_score(
                type(self.estimator)(**{**self.estimator.get_params(), **params}),
                X, y, cv=self.cv
            )
            mean_score = np.mean(scores)
            results['params'].append(params)
            results['mean_test_score'].append(mean_score)
            if mean_score > best_score:
                best_score = mean_score
                self.best_params_ = params
                self.best_score_ = mean_score
        self.cv_results_ = results
        # Refit on full data with best params
        self.best_estimator_ = type(self.estimator)(
            **{**self.estimator.get_params(), **self.best_params_}
        )
        self.best_estimator_.fit(X, y)
        return self

    def predict(self, X):
        return self.best_estimator_.predict(X)

    def score(self, X, y):
        return self.best_estimator_.score(X, y)

    def get_params(self, deep=True):
        return {
            'estimator': self.estimator,
            'param_grid': self.param_grid,
            'cv': self.cv,
            'scoring': self.scoring
        }
