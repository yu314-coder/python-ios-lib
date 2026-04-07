"""Base classes for sklearn estimators."""
import numpy as np


class BaseEstimator:
    def get_params(self, deep=True):
        import inspect
        init = self.__class__.__init__
        params = inspect.signature(init).parameters
        return {k: getattr(self, k) for k in params if k != 'self' and hasattr(self, k)}

    def set_params(self, **params):
        for k, v in params.items():
            setattr(self, k, v)
        return self


class ClassifierMixin:
    def score(self, X, y):
        return np.mean(self.predict(X) == np.asarray(y))


class RegressorMixin:
    def score(self, X, y):
        y = np.asarray(y, dtype=float)
        y_pred = self.predict(X)
        ss_res = np.sum((y - y_pred) ** 2)
        ss_tot = np.sum((y - np.mean(y)) ** 2)
        return 1.0 - ss_res / max(ss_tot, 1e-15)


class TransformerMixin:
    def fit_transform(self, X, y=None):
        return self.fit(X, y).transform(X)
