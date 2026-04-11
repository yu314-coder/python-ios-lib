# scikit-learn (sklearn) - Pure NumPy Implementation

> **Version:** 1.8.0-offlinai | **Type:** Pure Python/NumPy | **Size:** 12,077 lines across 40 modules | **Location:** `sklearn/`

A from-scratch reimplementation of scikit-learn using only NumPy. No compiled extensions needed -- runs on iOS/iPadOS natively. Implements the full scikit-learn estimator API (`fit`, `predict`, `transform`, `score`, `get_params`, `set_params`).

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

## Module Reference

### `sklearn.linear_model` -- Linear Models

| Class | Key Parameters | Methods |
|-------|---------------|---------|
| `LinearRegression` | `fit_intercept` | `fit()`, `predict()`, `score()` |
| `Ridge` | `alpha`, `fit_intercept`, `solver` | `fit()`, `predict()`, `score()` |
| `Lasso` | `alpha`, `max_iter`, `tol` | `fit()`, `predict()`, `score()` |
| `ElasticNet` | `alpha`, `l1_ratio`, `max_iter`, `tol` | `fit()`, `predict()`, `score()` |
| `LogisticRegression` | `C`, `max_iter`, `lr`, `penalty`, `solver`, `multi_class` | `fit()`, `predict()`, `predict_proba()`, `score()`, `decision_function()` |
| `SGDClassifier` | `loss`, `alpha`, `max_iter`, `learning_rate`, `eta0`, `penalty` | `fit()`, `partial_fit()`, `predict()`, `decision_function()`, `score()` |
| `SGDRegressor` | `loss`, `alpha`, `max_iter`, `learning_rate`, `eta0`, `penalty` | `fit()`, `partial_fit()`, `predict()`, `score()` |
| `RidgeClassifier` | `alpha`, `fit_intercept` | `fit()`, `predict()`, `decision_function()`, `score()` |
| `Perceptron` | `alpha`, `max_iter`, `eta0`, `penalty` | `fit()`, `predict()`, `score()` |
| `BayesianRidge` | `max_iter`, `tol`, `alpha_1`, `alpha_2`, `lambda_1`, `lambda_2` | `fit()`, `predict()`, `score()` |
| `ARDRegression` | `max_iter`, `tol`, `alpha_1`, `alpha_2`, `lambda_1`, `lambda_2`, `threshold_lambda` | `fit()`, `predict()`, `score()` |
| `HuberRegressor` | `epsilon`, `max_iter`, `alpha` | `fit()`, `predict()`, `score()` |
| `Lars` | `n_nonzero_coefs`, `fit_intercept` | `fit()`, `predict()`, `score()` |
| `LassoLars` | `alpha`, `max_iter`, `fit_intercept` | `fit()`, `predict()`, `score()` |
| `OrthogonalMatchingPursuit` | `n_nonzero_coefs`, `tol` | `fit()`, `predict()`, `score()` |
| `PoissonRegressor` | `alpha`, `max_iter`, `tol` | `fit()`, `predict()`, `score()` |
| `GammaRegressor` | `alpha`, `max_iter`, `tol` | `fit()`, `predict()`, `score()` |
| `TweedieRegressor` | `power`, `alpha`, `max_iter`, `tol` | `fit()`, `predict()`, `score()` |

---

### `sklearn.tree` -- Decision Trees

| Class | Key Parameters | Methods |
|-------|---------------|---------|
| `DecisionTreeClassifier` | `max_depth`, `min_samples_split`, `min_samples_leaf`, `criterion`, `max_features`, `random_state` | `fit()`, `predict()`, `predict_proba()`, `score()`, `feature_importances_` |
| `DecisionTreeRegressor` | `max_depth`, `min_samples_split`, `min_samples_leaf`, `criterion`, `max_features`, `random_state` | `fit()`, `predict()`, `score()`, `feature_importances_` |
| `ExtraTreeClassifier` | `max_depth`, `min_samples_split`, `max_features`, `random_state` | `fit()`, `predict()`, `predict_proba()`, `score()` |
| `ExtraTreeRegressor` | `max_depth`, `min_samples_split`, `max_features`, `random_state` | `fit()`, `predict()`, `score()` |

---

### `sklearn.ensemble` -- Ensemble Methods

| Class | Key Parameters | Methods |
|-------|---------------|---------|
| `RandomForestClassifier` | `n_estimators`, `max_depth`, `max_features`, `min_samples_split`, `random_state`, `n_jobs` | `fit()`, `predict()`, `predict_proba()`, `score()`, `feature_importances_` |
| `RandomForestRegressor` | `n_estimators`, `max_depth`, `max_features`, `min_samples_split`, `random_state` | `fit()`, `predict()`, `score()`, `feature_importances_` |
| `GradientBoostingClassifier` | `n_estimators`, `learning_rate`, `max_depth`, `subsample`, `loss`, `random_state` | `fit()`, `predict()`, `predict_proba()`, `score()`, `feature_importances_` |
| `GradientBoostingRegressor` | `n_estimators`, `learning_rate`, `max_depth`, `subsample`, `loss`, `random_state` | `fit()`, `predict()`, `score()`, `feature_importances_` |
| `AdaBoostClassifier` | `n_estimators`, `learning_rate`, `random_state` | `fit()`, `predict()`, `predict_proba()`, `score()` |
| `AdaBoostRegressor` | `n_estimators`, `learning_rate`, `loss`, `random_state` | `fit()`, `predict()`, `score()` |
| `BaggingClassifier` | `n_estimators`, `max_samples`, `max_features`, `random_state` | `fit()`, `predict()`, `predict_proba()`, `score()` |
| `BaggingRegressor` | `n_estimators`, `max_samples`, `max_features`, `random_state` | `fit()`, `predict()`, `score()` |
| `ExtraTreesClassifier` | `n_estimators`, `max_depth`, `max_features`, `random_state` | `fit()`, `predict()`, `predict_proba()`, `score()`, `feature_importances_` |
| `ExtraTreesRegressor` | `n_estimators`, `max_depth`, `max_features`, `random_state` | `fit()`, `predict()`, `score()`, `feature_importances_` |
| `HistGradientBoostingClassifier` | `max_iter`, `learning_rate`, `max_depth`, `max_leaf_nodes`, `min_samples_leaf`, `l2_regularization` | `fit()`, `predict()`, `predict_proba()`, `score()` |
| `HistGradientBoostingRegressor` | `max_iter`, `learning_rate`, `max_depth`, `max_leaf_nodes`, `min_samples_leaf`, `l2_regularization` | `fit()`, `predict()`, `score()` |
| `IsolationForest` | `n_estimators`, `max_samples`, `contamination`, `random_state` | `fit()`, `predict()`, `decision_function()`, `score_samples()` |
| `VotingClassifier` | `estimators`, `voting` (`hard`/`soft`), `weights` | `fit()`, `predict()`, `predict_proba()`, `score()` |
| `VotingRegressor` | `estimators`, `weights` | `fit()`, `predict()`, `score()` |
| `StackingClassifier` | `estimators`, `final_estimator`, `cv` | `fit()`, `predict()`, `predict_proba()`, `score()` |
| `StackingRegressor` | `estimators`, `final_estimator`, `cv` | `fit()`, `predict()`, `score()` |

---

### `sklearn.cluster` -- Clustering

| Class | Key Parameters | Methods / Attributes |
|-------|---------------|---------------------|
| `KMeans` | `n_clusters`, `n_init`, `max_iter`, `random_state`, `init` | `fit()`, `predict()`, `fit_predict()`, `labels_`, `cluster_centers_`, `inertia_` |
| `MiniBatchKMeans` | `n_clusters`, `batch_size`, `max_iter`, `random_state` | `fit()`, `predict()`, `fit_predict()`, `partial_fit()`, `labels_`, `cluster_centers_` |
| `DBSCAN` | `eps`, `min_samples`, `metric` | `fit()`, `fit_predict()`, `labels_`, `core_sample_indices_` |
| `AgglomerativeClustering` | `n_clusters`, `linkage` (`single`/`complete`/`average`/`ward`), `distance_threshold` | `fit()`, `fit_predict()`, `labels_`, `n_clusters_` |
| `SpectralClustering` | `n_clusters`, `affinity`, `gamma`, `random_state` | `fit()`, `fit_predict()`, `labels_` |
| `MeanShift` | `bandwidth`, `seeds`, `bin_seeding` | `fit()`, `predict()`, `fit_predict()`, `labels_`, `cluster_centers_` |
| `OPTICS` | `min_samples`, `max_eps`, `metric`, `cluster_method` | `fit()`, `labels_`, `reachability_`, `ordering_` |
| `Birch` | `threshold`, `branching_factor`, `n_clusters` | `fit()`, `predict()`, `fit_predict()`, `labels_` |
| `AffinityPropagation` | `damping`, `max_iter`, `preference` | `fit()`, `predict()`, `fit_predict()`, `labels_`, `cluster_centers_indices_` |
| `BisectingKMeans` | `n_clusters`, `n_init`, `max_iter`, `random_state` | `fit()`, `predict()`, `fit_predict()`, `labels_` |
| `HDBSCAN` | `min_cluster_size`, `min_samples`, `cluster_selection_epsilon` | `fit()`, `fit_predict()`, `labels_`, `probabilities_` |
| `FeatureAgglomeration` | `n_clusters`, `linkage`, `distance_threshold` | `fit()`, `transform()`, `fit_transform()`, `labels_` |

---

### `sklearn.preprocessing` -- Data Preprocessing

| Class | Key Parameters | Methods |
|-------|---------------|---------|
| `StandardScaler` | `with_mean`, `with_std` | `fit()`, `transform()`, `fit_transform()`, `inverse_transform()` |
| `MinMaxScaler` | `feature_range` | `fit()`, `transform()`, `fit_transform()`, `inverse_transform()` |
| `RobustScaler` | `with_centering`, `with_scaling`, `quantile_range` | `fit()`, `transform()`, `fit_transform()`, `inverse_transform()` |
| `MaxAbsScaler` | -- | `fit()`, `transform()`, `fit_transform()`, `inverse_transform()` |
| `Normalizer` | `norm` (`l1`/`l2`/`max`) | `fit()`, `transform()`, `fit_transform()` |
| `Binarizer` | `threshold` | `fit()`, `transform()`, `fit_transform()` |
| `LabelEncoder` | -- | `fit()`, `transform()`, `fit_transform()`, `inverse_transform()`, `classes_` |
| `OneHotEncoder` | `sparse_output`, `handle_unknown`, `drop` | `fit()`, `transform()`, `fit_transform()`, `inverse_transform()`, `categories_` |
| `OrdinalEncoder` | `categories`, `handle_unknown` | `fit()`, `transform()`, `fit_transform()`, `inverse_transform()` |
| `LabelBinarizer` | `neg_label`, `pos_label` | `fit()`, `transform()`, `fit_transform()`, `inverse_transform()` |
| `PolynomialFeatures` | `degree`, `interaction_only`, `include_bias` | `fit()`, `transform()`, `fit_transform()`, `n_output_features_` |
| `PowerTransformer` | `method` (`yeo-johnson`/`box-cox`), `standardize` | `fit()`, `transform()`, `fit_transform()`, `inverse_transform()` |
| `QuantileTransformer` | `n_quantiles`, `output_distribution` (`uniform`/`normal`) | `fit()`, `transform()`, `fit_transform()`, `inverse_transform()` |
| `KBinsDiscretizer` | `n_bins`, `encode` (`ordinal`/`onehot`), `strategy` (`uniform`/`quantile`/`kmeans`) | `fit()`, `transform()`, `fit_transform()` |
| `FunctionTransformer` | `func`, `inverse_func` | `fit()`, `transform()`, `fit_transform()`, `inverse_transform()` |
| `SplineTransformer` | `n_knots`, `degree`, `knots` | `fit()`, `transform()`, `fit_transform()` |
| `TargetEncoder` | `categories`, `smooth` | `fit()`, `transform()`, `fit_transform()` |

---

### `sklearn.decomposition` -- Dimensionality Reduction

| Class | Key Parameters | Methods / Attributes |
|-------|---------------|---------------------|
| `PCA` | `n_components`, `whiten`, `svd_solver` | `fit()`, `transform()`, `fit_transform()`, `inverse_transform()`, `explained_variance_ratio_`, `components_` |
| `TruncatedSVD` | `n_components`, `n_iter`, `random_state` | `fit()`, `transform()`, `fit_transform()`, `explained_variance_ratio_`, `components_` |
| `NMF` | `n_components`, `init`, `max_iter`, `tol`, `random_state` | `fit()`, `transform()`, `fit_transform()`, `components_` |
| `FastICA` | `n_components`, `algorithm`, `max_iter`, `tol`, `random_state` | `fit()`, `transform()`, `fit_transform()`, `mixing_`, `components_` |
| `KernelPCA` | `n_components`, `kernel`, `gamma`, `degree` | `fit()`, `transform()`, `fit_transform()` |
| `IncrementalPCA` | `n_components`, `batch_size` | `fit()`, `transform()`, `partial_fit()`, `explained_variance_ratio_` |
| `LatentDirichletAllocation` | `n_components`, `max_iter`, `learning_method`, `random_state` | `fit()`, `transform()`, `fit_transform()`, `components_` |
| `SparsePCA` | `n_components`, `alpha`, `max_iter`, `random_state` | `fit()`, `transform()`, `fit_transform()`, `components_` |
| `FactorAnalysis` | `n_components`, `max_iter`, `tol` | `fit()`, `transform()`, `fit_transform()`, `components_` |
| `DictionaryLearning` | `n_components`, `alpha`, `max_iter`, `random_state` | `fit()`, `transform()`, `fit_transform()`, `components_` |
| `MiniBatchNMF` | `n_components`, `batch_size`, `max_iter`, `random_state` | `fit()`, `transform()`, `partial_fit()`, `components_` |

---

### `sklearn.neighbors` -- Nearest Neighbors

| Class | Key Parameters | Methods |
|-------|---------------|---------|
| `KNeighborsClassifier` | `n_neighbors`, `weights` (`uniform`/`distance`), `metric`, `p` | `fit()`, `predict()`, `predict_proba()`, `score()`, `kneighbors()` |
| `KNeighborsRegressor` | `n_neighbors`, `weights`, `metric`, `p` | `fit()`, `predict()`, `score()`, `kneighbors()` |
| `RadiusNeighborsClassifier` | `radius`, `weights`, `metric` | `fit()`, `predict()`, `predict_proba()`, `score()` |
| `RadiusNeighborsRegressor` | `radius`, `weights`, `metric` | `fit()`, `predict()`, `score()` |
| `NearestNeighbors` | `n_neighbors`, `radius`, `metric` | `fit()`, `kneighbors()`, `radius_neighbors()` |
| `NearestCentroid` | `metric`, `shrink_threshold` | `fit()`, `predict()`, `score()`, `centroids_` |
| `LocalOutlierFactor` | `n_neighbors`, `contamination`, `metric` | `fit()`, `fit_predict()`, `decision_function()`, `negative_outlier_factor_` |
| `KernelDensity` | `bandwidth`, `kernel`, `metric` | `fit()`, `score_samples()`, `score()`, `sample()` |

---

### `sklearn.svm` -- Support Vector Machines

| Class | Key Parameters | Methods |
|-------|---------------|---------|
| `SVC` | `C`, `kernel`, `gamma`, `degree`, `max_iter` | `fit()`, `predict()`, `decision_function()`, `score()` |
| `SVR` | `C`, `kernel`, `gamma`, `epsilon`, `max_iter` | `fit()`, `predict()`, `score()` |
| `LinearSVC` | `C`, `loss`, `penalty`, `max_iter`, `dual` | `fit()`, `predict()`, `decision_function()`, `score()` |
| `LinearSVR` | `C`, `epsilon`, `loss`, `max_iter` | `fit()`, `predict()`, `score()` |
| `NuSVC` | `nu`, `kernel`, `gamma`, `degree`, `max_iter` | `fit()`, `predict()`, `decision_function()`, `score()` |
| `NuSVR` | `nu`, `C`, `kernel`, `gamma`, `max_iter` | `fit()`, `predict()`, `score()` |
| `OneClassSVM` | `nu`, `kernel`, `gamma`, `degree` | `fit()`, `predict()`, `decision_function()`, `score_samples()` |

---

### `sklearn.naive_bayes` -- Naive Bayes

| Class | Key Parameters | Methods |
|-------|---------------|---------|
| `GaussianNB` | `var_smoothing`, `priors` | `fit()`, `predict()`, `predict_proba()`, `predict_log_proba()`, `score()`, `partial_fit()` |
| `MultinomialNB` | `alpha`, `fit_prior` | `fit()`, `predict()`, `predict_proba()`, `predict_log_proba()`, `score()`, `partial_fit()` |
| `BernoulliNB` | `alpha`, `binarize`, `fit_prior` | `fit()`, `predict()`, `predict_proba()`, `predict_log_proba()`, `score()`, `partial_fit()` |
| `ComplementNB` | `alpha`, `norm` | `fit()`, `predict()`, `predict_proba()`, `score()` |
| `CategoricalNB` | `alpha`, `fit_prior` | `fit()`, `predict()`, `predict_proba()`, `score()` |

---

### `sklearn.neural_network` -- Neural Networks

| Class | Key Parameters | Methods |
|-------|---------------|---------|
| `MLPClassifier` | `hidden_layer_sizes`, `activation` (`relu`/`tanh`/`logistic`), `solver` (`adam`/`sgd`), `max_iter`, `learning_rate_init`, `alpha` | `fit()`, `predict()`, `predict_proba()`, `score()`, `partial_fit()` |
| `MLPRegressor` | `hidden_layer_sizes`, `activation`, `solver`, `max_iter`, `learning_rate_init`, `alpha` | `fit()`, `predict()`, `score()`, `partial_fit()` |

---

### `sklearn.gaussian_process` -- Gaussian Processes

| Class | Key Parameters | Methods |
|-------|---------------|---------|
| `GaussianProcessClassifier` | `kernel`, `n_restarts_optimizer`, `random_state` | `fit()`, `predict()`, `predict_proba()`, `score()`, `log_marginal_likelihood()` |
| `GaussianProcessRegressor` | `kernel`, `alpha`, `n_restarts_optimizer`, `random_state` | `fit()`, `predict()`, `score()`, `log_marginal_likelihood()` |

**Kernels:** `RBF`, `Matern`, `RationalQuadratic`, `ExpSineSquared`, `DotProduct`, `WhiteKernel`, `ConstantKernel`, `Sum`, `Product`

---

### `sklearn.discriminant_analysis` -- Discriminant Analysis

| Class | Key Parameters | Methods |
|-------|---------------|---------|
| `LinearDiscriminantAnalysis` | `n_components`, `solver`, `shrinkage` | `fit()`, `predict()`, `predict_proba()`, `transform()`, `score()` |
| `QuadraticDiscriminantAnalysis` | `reg_param` | `fit()`, `predict()`, `predict_proba()`, `score()` |

---

### `sklearn.mixture` -- Gaussian Mixture Models

| Class | Key Parameters | Methods |
|-------|---------------|---------|
| `GaussianMixture` | `n_components`, `covariance_type` (`full`/`tied`/`diag`/`spherical`), `max_iter`, `random_state` | `fit()`, `predict()`, `predict_proba()`, `score()`, `score_samples()`, `sample()`, `bic()`, `aic()` |
| `BayesianGaussianMixture` | `n_components`, `covariance_type`, `weight_concentration_prior_type`, `max_iter` | `fit()`, `predict()`, `predict_proba()`, `score()`, `score_samples()` |

---

### `sklearn.model_selection` -- Model Selection & Validation

| Function / Class | Description |
|-----------------|-------------|
| `train_test_split(X, y, test_size, random_state, stratify)` | Split arrays into train/test subsets |
| `cross_val_score(estimator, X, y, cv, scoring)` | Evaluate estimator by cross-validation |
| `cross_validate(estimator, X, y, cv, scoring, return_train_score)` | Evaluate with multiple metrics |
| `learning_curve(estimator, X, y, train_sizes, cv)` | Generate learning curve data |
| `validation_curve(estimator, X, y, param_name, param_range, cv)` | Generate validation curve data |
| `KFold(n_splits, shuffle, random_state)` | K-fold cross-validation splitter |
| `StratifiedKFold(n_splits, shuffle, random_state)` | Stratified K-fold (preserves class ratios) |
| `LeaveOneOut()` | Leave-one-out cross-validation |
| `TimeSeriesSplit(n_splits, max_train_size)` | Time-series-aware cross-validation |
| `ShuffleSplit(n_splits, test_size, random_state)` | Random permutation cross-validation |
| `RepeatedKFold(n_splits, n_repeats, random_state)` | Repeated K-fold |
| `RepeatedStratifiedKFold(n_splits, n_repeats, random_state)` | Repeated stratified K-fold |
| `GroupKFold(n_splits)` | K-fold with non-overlapping groups |
| `GridSearchCV(estimator, param_grid, cv, scoring, refit)` | Exhaustive grid search over parameters |
| `RandomizedSearchCV(estimator, param_distributions, n_iter, cv, scoring)` | Randomized parameter search |

---

### `sklearn.metrics` -- Evaluation Metrics (38 functions)

#### Classification Metrics

| Function | Description |
|----------|-------------|
| `accuracy_score(y_true, y_pred)` | Fraction of correct predictions |
| `balanced_accuracy_score(y_true, y_pred)` | Balanced accuracy (macro recall) |
| `precision_score(y_true, y_pred, average)` | Precision (positive predictive value) |
| `recall_score(y_true, y_pred, average)` | Recall (sensitivity / true positive rate) |
| `f1_score(y_true, y_pred, average)` | F1 score (harmonic mean of precision/recall) |
| `fbeta_score(y_true, y_pred, beta, average)` | F-beta score with adjustable beta |
| `confusion_matrix(y_true, y_pred)` | Confusion matrix (NxN array) |
| `classification_report(y_true, y_pred)` | Text report with precision/recall/F1 per class |
| `roc_auc_score(y_true, y_score)` | Area under ROC curve |
| `roc_curve(y_true, y_score)` | ROC curve (fpr, tpr, thresholds) |
| `precision_recall_curve(y_true, probas_pred)` | Precision-recall curve |
| `average_precision_score(y_true, y_score)` | Average precision (area under PR curve) |
| `log_loss(y_true, y_pred)` | Log loss / cross-entropy |
| `brier_score_loss(y_true, y_prob)` | Brier score for probabilistic predictions |
| `cohen_kappa_score(y1, y2)` | Cohen's kappa inter-rater agreement |
| `matthews_corrcoef(y_true, y_pred)` | Matthews correlation coefficient |
| `hamming_loss(y_true, y_pred)` | Hamming loss (fraction of wrong labels) |
| `jaccard_score(y_true, y_pred, average)` | Jaccard similarity coefficient |
| `zero_one_loss(y_true, y_pred)` | Zero-one loss (fraction incorrect) |
| `hinge_loss(y_true, pred_decision)` | Average hinge loss |
| `top_k_accuracy_score(y_true, y_score, k)` | Top-k accuracy |

#### Regression Metrics

| Function | Description |
|----------|-------------|
| `mean_squared_error(y_true, y_pred)` | Mean squared error |
| `mean_absolute_error(y_true, y_pred)` | Mean absolute error |
| `root_mean_squared_error(y_true, y_pred)` | Root mean squared error |
| `median_absolute_error(y_true, y_pred)` | Median absolute error |
| `r2_score(y_true, y_pred)` | R-squared (coefficient of determination) |
| `explained_variance_score(y_true, y_pred)` | Explained variance |
| `max_error(y_true, y_pred)` | Maximum residual error |
| `mean_absolute_percentage_error(y_true, y_pred)` | MAPE |
| `mean_squared_log_error(y_true, y_pred)` | MSLE |
| `mean_pinball_loss(y_true, y_pred, alpha)` | Pinball (quantile) loss |
| `d2_pinball_score(y_true, y_pred, alpha)` | D2 pinball score |

#### Clustering Metrics

| Function | Description |
|----------|-------------|
| `silhouette_score(X, labels)` | Mean silhouette coefficient |
| `silhouette_samples(X, labels)` | Per-sample silhouette values |
| `calinski_harabasz_score(X, labels)` | Variance ratio criterion |
| `davies_bouldin_score(X, labels)` | Davies-Bouldin index |
| `adjusted_rand_score(labels_true, labels_pred)` | Adjusted Rand index |
| `adjusted_mutual_info_score(labels_true, labels_pred)` | Adjusted mutual information |
| `normalized_mutual_info_score(labels_true, labels_pred)` | Normalized mutual information |

#### Pairwise & Distance

| Function | Description |
|----------|-------------|
| `pairwise_distances(X, Y, metric)` | Pairwise distance matrix |
| `euclidean_distances(X, Y)` | Euclidean distance matrix |
| `cosine_similarity(X, Y)` | Cosine similarity matrix |

---

### `sklearn.datasets` -- Dataset Generators & Loaders

| Function | Description |
|----------|-------------|
| `make_classification(n_samples, n_features, n_informative, n_classes, random_state)` | Synthetic classification dataset |
| `make_regression(n_samples, n_features, n_informative, noise, random_state)` | Synthetic regression dataset |
| `make_blobs(n_samples, centers, n_features, cluster_std, random_state)` | Gaussian blob clusters |
| `make_moons(n_samples, noise, random_state)` | Two interleaving half-circles |
| `make_circles(n_samples, noise, factor, random_state)` | Concentric circles |
| `make_swiss_roll(n_samples, noise, random_state)` | 3D Swiss roll manifold |
| `make_s_curve(n_samples, noise, random_state)` | 3D S-curve manifold |
| `make_friedman1(n_samples, n_features, noise, random_state)` | Friedman #1 regression |
| `make_friedman2(n_samples, noise, random_state)` | Friedman #2 regression |
| `make_friedman3(n_samples, noise, random_state)` | Friedman #3 regression |
| `load_iris()` | 150 samples, 4 features, 3 classes (setosa/versicolor/virginica) |
| `load_digits()` | 1,797 samples, 64 features (8x8 pixel images), 10 classes |
| `load_wine()` | 178 samples, 13 features, 3 classes (wine cultivars) |
| `load_breast_cancer()` | 569 samples, 30 features, 2 classes (malignant/benign) |
| `load_diabetes()` | 442 samples, 10 features (regression target: disease progression) |

All loaders return a dict with keys: `data`, `target`, `feature_names`, `target_names`, `DESCR`.

---

### `sklearn.manifold` -- Manifold Learning

| Class | Key Parameters | Methods |
|-------|---------------|---------|
| `TSNE` | `n_components`, `perplexity`, `learning_rate`, `n_iter`, `random_state`, `metric` | `fit_transform()`, `embedding_` |
| `MDS` | `n_components`, `metric`, `max_iter`, `random_state` | `fit()`, `fit_transform()`, `embedding_`, `stress_` |
| `Isomap` | `n_components`, `n_neighbors` | `fit()`, `transform()`, `fit_transform()` |
| `LocallyLinearEmbedding` | `n_components`, `n_neighbors`, `method` (`standard`/`modified`/`hessian`/`ltsa`) | `fit()`, `transform()`, `fit_transform()` |
| `SpectralEmbedding` | `n_components`, `affinity`, `gamma`, `random_state` | `fit()`, `fit_transform()`, `embedding_` |

---

### `sklearn.pipeline` -- Pipeline Utilities

| Class / Function | Description |
|-----------------|-------------|
| `Pipeline(steps)` | Chain of transforms with a final estimator. Supports `fit()`, `predict()`, `transform()`, `score()`, `set_params()`, `get_params()` |
| `make_pipeline(*steps)` | Convenience constructor for Pipeline (auto-generates step names) |
| `FeatureUnion(transformer_list)` | Concatenate results of multiple transformers |

---

### `sklearn.compose` -- Column Transformers

| Class | Description |
|-------|-------------|
| `ColumnTransformer(transformers, remainder)` | Apply different transformers to different columns. `transformers` is a list of `(name, transformer, columns)` tuples. `remainder='drop'` or `'passthrough'` |
| `make_column_transformer(*transformers)` | Convenience constructor for ColumnTransformer |
| `make_column_selector(pattern, dtype_include, dtype_exclude)` | Column selector for ColumnTransformer |
| `TransformedTargetRegressor(regressor, transformer)` | Transform target before fitting a regressor |

---

### `sklearn.impute` -- Missing Value Imputation

| Class | Key Parameters | Methods |
|-------|---------------|---------|
| `SimpleImputer` | `strategy` (`mean`/`median`/`most_frequent`/`constant`), `fill_value` | `fit()`, `transform()`, `fit_transform()` |
| `KNNImputer` | `n_neighbors`, `weights`, `metric` | `fit()`, `transform()`, `fit_transform()` |
| `IterativeImputer` | `estimator`, `max_iter`, `random_state` | `fit()`, `transform()`, `fit_transform()` |
| `MissingIndicator` | `features` (`missing-only`/`all`) | `fit()`, `transform()`, `fit_transform()` |

---

### `sklearn.feature_extraction` -- Feature Extraction

| Class | Description |
|-------|-------------|
| `DictVectorizer(sparse)` | Convert list of dicts to feature matrix |
| `text.CountVectorizer(max_features, stop_words, ngram_range)` | Convert text to token count matrix |
| `text.TfidfVectorizer(max_features, stop_words, ngram_range)` | Convert text to TF-IDF matrix |
| `text.TfidfTransformer(norm, use_idf)` | Transform count matrix to TF-IDF |
| `text.HashingVectorizer(n_features)` | Hash-based text vectorization |

---

### `sklearn.feature_selection` -- Feature Selection

| Class | Description |
|-------|-------------|
| `SelectKBest(score_func, k)` | Select K highest-scoring features |
| `SelectPercentile(score_func, percentile)` | Select features by percentile |
| `VarianceThreshold(threshold)` | Remove low-variance features |
| `RFE(estimator, n_features_to_select)` | Recursive feature elimination |
| `RFECV(estimator, cv)` | RFE with cross-validated feature count |
| `SelectFromModel(estimator, threshold)` | Select features from model importance |
| `SequentialFeatureSelector(estimator, n_features_to_select, direction)` | Forward/backward feature selection |

**Score functions:** `f_classif`, `f_regression`, `chi2`, `mutual_info_classif`, `mutual_info_regression`

---

### `sklearn.calibration` -- Probability Calibration

| Class | Key Parameters | Methods |
|-------|---------------|---------|
| `CalibratedClassifierCV` | `estimator`, `method` (`sigmoid`/`isotonic`), `cv` | `fit()`, `predict()`, `predict_proba()`, `score()` |

| Function | Description |
|----------|-------------|
| `calibration_curve(y_true, y_prob, n_bins)` | Compute true and predicted probabilities for calibration plot |

---

### `sklearn.inspection` -- Model Inspection

| Function | Description |
|----------|-------------|
| `permutation_importance(estimator, X, y, n_repeats, scoring)` | Permutation-based feature importance |
| `partial_dependence(estimator, X, features)` | Partial dependence of features |
| `PartialDependenceDisplay.from_estimator(estimator, X, features)` | Plot partial dependence |

---

### `sklearn.multiclass` -- Multiclass Strategies

| Class | Description |
|-------|-------------|
| `OneVsRestClassifier(estimator)` | One-vs-rest (OVR) multiclass strategy |
| `OneVsOneClassifier(estimator)` | One-vs-one (OVO) multiclass strategy |
| `OutputCodeClassifier(estimator, code_size)` | Error-correcting output codes |

---

### `sklearn.multioutput` -- Multi-Output

| Class | Description |
|-------|-------------|
| `MultiOutputClassifier(estimator)` | Multi-target classification |
| `MultiOutputRegressor(estimator)` | Multi-target regression |
| `ClassifierChain(base_estimator, order)` | Chained multi-label classification |
| `RegressorChain(base_estimator, order)` | Chained multi-target regression |

---

### `sklearn.semi_supervised` -- Semi-Supervised Learning

| Class | Key Parameters | Methods |
|-------|---------------|---------|
| `LabelPropagation` | `kernel`, `gamma`, `n_neighbors`, `max_iter` | `fit()`, `predict()`, `predict_proba()`, `score()` |
| `LabelSpreading` | `kernel`, `gamma`, `alpha`, `max_iter` | `fit()`, `predict()`, `predict_proba()`, `score()` |
| `SelfTrainingClassifier` | `base_estimator`, `threshold`, `max_iter` | `fit()`, `predict()`, `predict_proba()`, `score()` |

---

### `sklearn.isotonic` -- Isotonic Regression

| Class | Key Parameters | Methods |
|-------|---------------|---------|
| `IsotonicRegression` | `increasing`, `out_of_bounds` | `fit()`, `predict()`, `transform()`, `score()` |

---

### `sklearn.kernel_approximation` -- Kernel Approximation

| Class | Description |
|-------|-------------|
| `RBFSampler(gamma, n_components)` | Approximate RBF kernel via random Fourier features |
| `Nystroem(kernel, gamma, n_components)` | Approximate kernel map using Nystroem method |
| `AdditiveChi2Sampler(sample_steps)` | Approximate additive chi-squared kernel |

---

### `sklearn.cross_decomposition` -- Cross Decomposition

| Class | Description |
|-------|-------------|
| `PLSRegression(n_components)` | Partial Least Squares regression |
| `PLSCanonical(n_components)` | Canonical PLS |
| `CCA(n_components)` | Canonical Correlation Analysis |

---

### `sklearn.base` -- Base Classes & Utilities

| Function / Class | Description |
|-----------------|-------------|
| `BaseEstimator` | Base class with `get_params()` / `set_params()` |
| `ClassifierMixin` | Mixin adding `score()` for classifiers |
| `RegressorMixin` | Mixin adding `score()` for regressors |
| `TransformerMixin` | Mixin adding `fit_transform()` |
| `ClusterMixin` | Mixin adding `fit_predict()` |
| `clone(estimator)` | Create a new estimator with same parameters |

---

## Example: Full Pipeline

```python
from sklearn.pipeline import Pipeline
from sklearn.compose import ColumnTransformer
from sklearn.preprocessing import StandardScaler, OneHotEncoder
from sklearn.impute import SimpleImputer
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.model_selection import cross_val_score
from sklearn.datasets import make_classification

X, y = make_classification(n_samples=500, n_features=10, random_state=42)
pipe = Pipeline([
    ('scaler', StandardScaler()),
    ('clf', GradientBoostingClassifier(n_estimators=50, max_depth=3))
])
scores = cross_val_score(pipe, X, y, cv=5)
print(f"CV Accuracy: {scores.mean():.3f} +/- {scores.std():.3f}")
```

---

## Compatibility Notes

- All estimators follow the scikit-learn API: `fit()`, `predict()`, `transform()`, `score()`, `get_params()`, `set_params()`
- NumPy arrays are used throughout (no pandas dependency)
- Random states are reproducible via `random_state` parameter
- No sparse matrix support (all operations use dense arrays)
- No joblib parallelism (`n_jobs` parameter is accepted but ignored)
