# scikit-learn (sklearn) - Pure NumPy Implementation

> **Version:** 1.0.0-offlinai | **Type:** Pure Python/NumPy | **Location:** `sklearn/`

A from-scratch reimplementation of scikit-learn using only NumPy. No compiled extensions needed - runs on iOS/iPadOS natively.

---

## Quick Start

```python
from sklearn.datasets import make_classification
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score

X, y = make_classification(n_samples=200, n_features=4, random_state=42)
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.3)

clf = RandomForestClassifier(n_estimators=10, max_depth=5)
clf.fit(X_train, y_train)
print(f"Accuracy: {accuracy_score(y_test, clf.predict(X_test)):.3f}")
```

---

## Implemented Classes & Functions

### Linear Models - `sklearn.linear_model`

| Class | Parameters | Methods |
|-------|-----------|---------|
| `LinearRegression` | `fit_intercept` | `fit()`, `predict()`, `score()` |
| `Ridge` | `alpha`, `fit_intercept` | `fit()`, `predict()`, `score()` |
| `Lasso` | `alpha`, `max_iter`, `tol` | `fit()`, `predict()`, `score()` |
| `LogisticRegression` | `max_iter`, `C`, `lr` | `fit()`, `predict()`, `predict_proba()`, `score()` |

```python
from sklearn.linear_model import LogisticRegression
from sklearn.datasets import make_moons

X, y = make_moons(n_samples=200, noise=0.2, random_state=42)
clf = LogisticRegression(max_iter=500)
clf.fit(X, y)
print(f"Accuracy: {clf.score(X, y):.3f}")
print(f"Probabilities: {clf.predict_proba(X[:3]).round(3)}")
```

### Tree Models - `sklearn.tree`

| Class | Parameters | Methods |
|-------|-----------|---------|
| `DecisionTreeClassifier` | `max_depth`, `min_samples_split` | `fit()`, `predict()`, `score()` |
| `DecisionTreeRegressor` | `max_depth`, `min_samples_split` | `fit()`, `predict()`, `score()` |

### Nearest Neighbors - `sklearn.neighbors`

| Class | Parameters | Methods |
|-------|-----------|---------|
| `KNeighborsClassifier` | `n_neighbors`, `weights` | `fit()`, `predict()`, `score()` |
| `KNeighborsRegressor` | `n_neighbors`, `weights` | `fit()`, `predict()`, `score()` |

### Ensemble Methods - `sklearn.ensemble`

| Class | Parameters |
|-------|-----------|
| `RandomForestClassifier` | `n_estimators`, `max_depth`, `max_features`, `random_state` |
| `RandomForestRegressor` | `n_estimators`, `max_depth`, `max_features` |
| `GradientBoostingClassifier` | `n_estimators`, `learning_rate`, `max_depth` |
| `GradientBoostingRegressor` | `n_estimators`, `learning_rate`, `max_depth` |
| `AdaBoostClassifier` | `n_estimators`, `learning_rate` |
| `BaggingClassifier` | `n_estimators`, `max_samples` |

```python
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.datasets import load_iris
from sklearn.model_selection import cross_val_score

X, y = load_iris()['data'], load_iris()['target']
clf = GradientBoostingClassifier(n_estimators=50, max_depth=3)
scores = cross_val_score(clf, X, y, cv=5)
print(f"CV Accuracy: {scores.mean():.3f} +/- {scores.std():.3f}")
```

### Clustering - `sklearn.cluster`

| Class | Parameters |
|-------|-----------|
| `KMeans` | `n_clusters`, `n_init`, `max_iter`, `random_state` |
| `DBSCAN` | `eps`, `min_samples` |
| `AgglomerativeClustering` | `n_clusters`, `linkage` (single/complete/average) |

```python
from sklearn.datasets import make_blobs
from sklearn.cluster import KMeans
from sklearn.metrics import silhouette_score

X, _ = make_blobs(n_samples=300, centers=4, random_state=42)
km = KMeans(n_clusters=4, random_state=42).fit(X)
print(f"Silhouette: {silhouette_score(X, km.labels_):.3f}")
print(f"Inertia: {km.inertia_:.1f}")
```

### SVM - `sklearn.svm`

| Class | Parameters |
|-------|-----------|
| `SVC` | `C`, `max_iter`, `lr` |
| `SVR` | `C`, `epsilon` |

### Naive Bayes - `sklearn.naive_bayes`

| Class | Parameters |
|-------|-----------|
| `GaussianNB` | `var_smoothing` |
| `MultinomialNB` | `alpha` |
| `BernoulliNB` | `alpha`, `binarize` |

### Preprocessing - `sklearn.preprocessing`

| Class | Key Methods |
|-------|------------|
| `StandardScaler` | `fit()`, `transform()`, `inverse_transform()` |
| `MinMaxScaler` | `fit()`, `transform()`, `inverse_transform()` |
| `RobustScaler` | `fit()`, `transform()` |
| `LabelEncoder` | `fit()`, `transform()`, `inverse_transform()` |
| `OneHotEncoder` | `fit()`, `transform()` |
| `PolynomialFeatures` | `fit()`, `transform()` |

```python
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import make_pipeline
from sklearn.linear_model import LogisticRegression

pipe = make_pipeline(StandardScaler(), LogisticRegression(max_iter=500))
pipe.fit(X_train, y_train)
print(f"Pipeline accuracy: {pipe.score(X_test, y_test):.3f}")
```

### Decomposition - `sklearn.decomposition`

| Class | Parameters |
|-------|-----------|
| `PCA` | `n_components` |
| `TruncatedSVD` | `n_components` |

### Model Selection - `sklearn.model_selection`

| Function/Class | Description |
|---------------|-------------|
| `train_test_split(X, y, test_size=0.3)` | Split data into train/test |
| `cross_val_score(est, X, y, cv=5)` | K-fold cross-validation |
| `StratifiedKFold(n_splits=5)` | Stratified K-fold splitter |
| `GridSearchCV(est, param_grid, cv=5)` | Grid search hyperparameter tuning |

### Metrics - `sklearn.metrics`

| Function | Type |
|----------|------|
| `accuracy_score(y_true, y_pred)` | Classification |
| `confusion_matrix(y_true, y_pred)` | Classification |
| `classification_report(y_true, y_pred)` | Classification |
| `precision_score`, `recall_score`, `f1_score` | Classification |
| `roc_auc_score(y_true, y_score)` | Classification |
| `mean_squared_error`, `mean_absolute_error` | Regression |
| `r2_score(y_true, y_pred)` | Regression |
| `silhouette_score(X, labels)` | Clustering |

### Datasets - `sklearn.datasets`

| Function | Description |
|----------|-------------|
| `make_classification(n_samples, n_features)` | Synthetic classification |
| `make_regression(n_samples, n_features)` | Synthetic regression |
| `make_blobs(n_samples, centers)` | Gaussian blobs |
| `make_moons(n_samples, noise)` | Half-circle shapes |
| `make_circles(n_samples, noise)` | Concentric circles |
| `load_iris()` | 150 samples, 4 features, 3 classes |
| `load_digits()` | 1797 samples, 64 features, 10 classes |

---

## Not Implemented

- Non-linear SVM kernels (RBF, polynomial, sigmoid)
- Sparse matrix support
- Feature selection (SelectKBest, RFE, etc.)
- Manifold learning (TSNE, Isomap, MDS)
- Spectral clustering, HDBSCAN
- Multi-output classification/regression
- Online learning (partial_fit)
- Probability calibration
