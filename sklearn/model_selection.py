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
