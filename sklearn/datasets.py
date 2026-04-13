"""sklearn.datasets — synthetic data generation for OfflinAi."""
import numpy as np


def make_classification(n_samples=100, n_features=20, n_informative=2, n_redundant=2,
                        n_clusters_per_class=1, n_classes=2, random_state=None, **kwargs):
    """Generate random classification data."""
    rng = np.random.RandomState(random_state)
    n_informative = min(n_informative, n_features)
    X = rng.randn(n_samples, n_features)
    # Create labels based on informative features
    w = rng.randn(n_informative)
    scores = X[:, :n_informative] @ w
    if n_classes == 2:
        y = (scores > np.median(scores)).astype(int)
    else:
        y = np.digitize(scores, np.percentile(scores, np.linspace(0, 100, n_classes + 1)[1:-1]))
    return X, y


def make_regression(n_samples=100, n_features=1, n_informative=1, noise=10.0,
                    random_state=None, **kwargs):
    """Generate random regression data."""
    rng = np.random.RandomState(random_state)
    n_informative = min(n_informative, n_features)
    X = rng.randn(n_samples, n_features)
    w = rng.randn(n_informative) * 10
    y = X[:, :n_informative] @ w + noise * rng.randn(n_samples)
    return X, y


def make_blobs(n_samples=100, n_features=2, centers=3, cluster_std=1.0,
               random_state=None, **kwargs):
    """Generate isotropic Gaussian blobs for clustering."""
    rng = np.random.RandomState(random_state)
    if isinstance(centers, int):
        centers_arr = rng.randn(centers, n_features) * 5
    else:
        centers_arr = np.asarray(centers)
    n_centers = len(centers_arr)
    n_per = n_samples // n_centers
    X_list, y_list = [], []
    for i, center in enumerate(centers_arr):
        n_i = n_per if i < n_centers - 1 else n_samples - n_per * (n_centers - 1)
        X_list.append(center + cluster_std * rng.randn(n_i, n_features))
        y_list.append(np.full(n_i, i, dtype=int))
    X = np.vstack(X_list)
    y = np.concatenate(y_list)
    # Shuffle
    idx = rng.permutation(n_samples)
    return X[idx], y[idx]


def make_moons(n_samples=100, noise=0.1, random_state=None):
    """Generate two interleaving half circles."""
    rng = np.random.RandomState(random_state)
    n_half = n_samples // 2
    outer = np.linspace(0, np.pi, n_half)
    inner = np.linspace(0, np.pi, n_samples - n_half)
    X = np.vstack([
        np.column_stack([np.cos(outer), np.sin(outer)]),
        np.column_stack([1 - np.cos(inner), 1 - np.sin(inner) - 0.5])
    ])
    y = np.concatenate([np.zeros(n_half, dtype=int), np.ones(n_samples - n_half, dtype=int)])
    X += noise * rng.randn(*X.shape)
    idx = rng.permutation(n_samples)
    return X[idx], y[idx]


def make_circles(n_samples=100, noise=0.05, factor=0.5, random_state=None):
    """Generate concentric circles."""
    rng = np.random.RandomState(random_state)
    n_half = n_samples // 2
    theta_outer = np.linspace(0, 2*np.pi, n_half, endpoint=False)
    theta_inner = np.linspace(0, 2*np.pi, n_samples - n_half, endpoint=False)
    X = np.vstack([
        np.column_stack([np.cos(theta_outer), np.sin(theta_outer)]),
        np.column_stack([factor * np.cos(theta_inner), factor * np.sin(theta_inner)])
    ])
    y = np.concatenate([np.zeros(n_half, dtype=int), np.ones(n_samples - n_half, dtype=int)])
    X += noise * rng.randn(*X.shape)
    idx = rng.permutation(n_samples)
    return X[idx], y[idx]


def load_iris():
    """Return a simple version of the iris dataset."""
    rng = np.random.RandomState(42)
    # Generate synthetic iris-like data: 3 classes, 4 features, 150 samples
    X, y = make_blobs(n_samples=150, n_features=4, centers=3, cluster_std=0.8, random_state=42)
    feature_names = ['sepal length', 'sepal width', 'petal length', 'petal width']
    target_names = ['setosa', 'versicolor', 'virginica']
    return type('Bunch', (), {
        'data': X, 'target': y, 'feature_names': feature_names,
        'target_names': target_names, 'DESCR': 'Synthetic iris dataset'
    })()


def load_digits():
    """Return synthetic digits-like dataset."""
    rng = np.random.RandomState(42)
    X, y = make_classification(n_samples=1797, n_features=64, n_classes=10,
                                n_informative=10, random_state=42)
    return type('Bunch', (), {
        'data': X, 'target': y, 'DESCR': 'Synthetic digits dataset'
    })()
