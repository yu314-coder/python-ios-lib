# scikit-learn (sklearn)

**Pure NumPy reimplementation** | v1.0.0-offlinai | 12,000+ lines | 40 modules

> Runs 100% offline on iPad. No compiled C extensions — everything is pure Python + NumPy.

---

## What's Included

### Classification & Regression

| Module | Classes | Notes |
|--------|---------|-------|
| `linear_model` | `LinearRegression`, `Ridge`, `Lasso`, `ElasticNet`, `SGDClassifier`, `SGDRegressor`, `LogisticRegression`, `Perceptron`, `PassiveAggressiveClassifier`, `BayesianRidge`, `ARDRegression`, `HuberRegressor`, `RANSACRegressor`, `TheilSenRegressor`, `QuantileRegressor`, `OrthogonalMatchingPursuit`, `Lars`, `LassoLars` | 18 classes |
| `tree` | `DecisionTreeClassifier`, `DecisionTreeRegressor` | Gini & variance splitting |
| `neighbors` | `KNeighborsClassifier`, `KNeighborsRegressor` | Brute-force, uniform/distance weights |
| `svm` | `SVC`, `SVR`, `LinearSVC`, `LinearSVR`, `NuSVC`, `NuSVR`, `OneClassSVM` | SGD-based linear SVM |
| `naive_bayes` | `GaussianNB`, `MultinomialNB`, `BernoulliNB`, `ComplementNB`, `CategoricalNB` | 5 variants |
| `neural_network` | `MLPClassifier`, `MLPRegressor` | Multi-layer perceptron with backprop |

### Ensemble Methods

| Class | Description |
|-------|-------------|
| `RandomForestClassifier` / `Regressor` | Bagged decision trees |
| `GradientBoostingClassifier` / `Regressor` | Gradient boosted trees |
| `HistGradientBoostingClassifier` / `Regressor` | Histogram-based gradient boosting |
| `AdaBoostClassifier` / `Regressor` | Adaptive boosting |
| `ExtraTreesClassifier` / `Regressor` | Extremely randomized trees |
| `BaggingClassifier` / `Regressor` | Bootstrap aggregating |
| `VotingClassifier` / `Regressor` | Soft/hard voting ensemble |
| `StackingClassifier` / `Regressor` | Stacked generalization |
| `IsolationForest` | Anomaly detection via random forests |

### Clustering

| Class | Description |
|-------|-------------|
| `KMeans`, `MiniBatchKMeans` | K-Means with k-means++ init |
| `DBSCAN` | Density-based spatial clustering |
| `AgglomerativeClustering` | Hierarchical (single, complete, average, ward) |
| `SpectralClustering` | Graph-based spectral method |
| `MeanShift` | Mode-seeking clustering |
| `OPTICS` | Ordering points for cluster structure |
| `Birch` | Balanced iterative reducing |
| `AffinityPropagation` | Message-passing clustering |
| `HDBSCAN` | Hierarchical DBSCAN |
| `GaussianMixture` (in `mixture`) | EM-based Gaussian mixture models |
| `BayesianGaussianMixture` | Variational inference GMM |
| `FeatureAgglomeration` | Feature-space hierarchical clustering |

### Preprocessing

| Class | Description |
|-------|-------------|
| `StandardScaler` | Zero-mean, unit-variance |
| `MinMaxScaler` | Scale to [0, 1] |
| `MaxAbsScaler` | Scale by max absolute value |
| `RobustScaler` | Median/IQR scaling |
| `Normalizer` | L1/L2 row normalization |
| `Binarizer` | Threshold binarization |
| `LabelEncoder` | String-to-int labels |
| `OneHotEncoder` | One-hot encoding |
| `OrdinalEncoder` | Ordinal encoding |
| `LabelBinarizer` | Multi-class binarization |
| `MultiLabelBinarizer` | Multi-label binarization |
| `PolynomialFeatures` | Polynomial cross-features |
| `FunctionTransformer` | Custom transform function |
| `PowerTransformer` | Yeo-Johnson / Box-Cox |
| `QuantileTransformer` | Quantile normalization |
| `KBinsDiscretizer` | Binning continuous features |
| `SplineTransformer` | B-spline feature expansion |
| `TargetEncoder` | Target-based encoding |

### Decomposition & Manifold

| Class | Description |
|-------|-------------|
| `PCA` | Principal Component Analysis |
| `TruncatedSVD` | SVD for sparse-like data |
| `KernelPCA` | Kernel-based PCA |
| `IncrementalPCA` | Batch-wise PCA |
| `FastICA` | Independent Component Analysis |
| `NMF` | Non-negative Matrix Factorization |
| `FactorAnalysis` | Factor analysis |
| `LatentDirichletAllocation` | Topic modeling |
| `DictionaryLearning` | Sparse coding |
| `SparsePCA` | Sparse PCA |
| `MiniBatchDictionaryLearning` | Online dictionary learning |
| `TSNE` (in `manifold`) | t-distributed SNE |
| `Isomap` | Isometric mapping |
| `MDS` | Multidimensional scaling |
| `LocallyLinearEmbedding` | LLE |
| `SpectralEmbedding` | Spectral embedding |

### Model Selection

| Item | Description |
|------|-------------|
| `train_test_split()` | Split with stratification |
| `cross_val_score()` | K-fold cross validation |
| `GridSearchCV` | Exhaustive grid search |
| `RandomizedSearchCV` | Random hyperparameter search |
| `KFold` / `StratifiedKFold` | K-fold splitters |
| `RepeatedKFold` | Repeated K-fold |
| `LeaveOneOut` / `LeavePOut` | LOO / LPO |
| `ShuffleSplit` / `StratifiedShuffleSplit` | Random splits |
| `GroupKFold` / `GroupShuffleSplit` | Group-aware splits |
| `TimeSeriesSplit` | Time-ordered splits |
| `ParameterGrid` / `ParameterSampler` | Parameter iteration |
| `learning_curve` / `validation_curve` | Diagnostic curves |
| `cross_validate` | Multi-metric CV |

### Metrics (38 functions)

Classification: `accuracy_score`, `precision_score`, `recall_score`, `f1_score`, `roc_auc_score`, `log_loss`, `confusion_matrix`, `classification_report`, `matthews_corrcoef`, `cohen_kappa_score`, `balanced_accuracy_score`, `top_k_accuracy_score`, `average_precision_score`, `brier_score_loss`, `hamming_loss`, `hinge_loss`, `jaccard_score`, `zero_one_loss`, `roc_curve`, `precision_recall_curve`

Regression: `mean_squared_error`, `mean_absolute_error`, `r2_score`, `mean_squared_log_error`, `median_absolute_error`, `explained_variance_score`, `max_error`, `mean_absolute_percentage_error`, `mean_pinball_loss`, `d2_pinball_score`

Clustering: `silhouette_score`, `silhouette_samples`, `calinski_harabasz_score`, `davies_bouldin_score`, `adjusted_rand_score`, `adjusted_mutual_info_score`, `normalized_mutual_info_score`, `homogeneity_completeness_v_measure`

### Pipeline & Datasets

| Item | Description |
|------|-------------|
| `Pipeline` | Chain transformers + estimator |
| `make_pipeline()` | Auto-named pipeline |
| `ColumnTransformer` | Per-column transformers |
| `FeatureUnion` | Parallel feature pipelines |
| `make_classification()` | Synthetic classification data |
| `make_regression()` | Synthetic regression data |
| `make_blobs()` | Gaussian blob clusters |
| `make_moons()` / `make_circles()` | Non-linear datasets |
| `load_iris()` | 150 samples, 4 features, 3 classes |
| `load_digits()` | 1,797 samples, 64 features, 10 classes |
| `load_wine()` | 178 samples, 13 features, 3 classes |
| `load_breast_cancer()` | 569 samples, 30 features, 2 classes |
| `load_diabetes()` | 442 samples, 10 features |
| `load_boston()` | 506 samples, 13 features |
| `load_linnerud()` | 20 samples, physiological data |
| `fetch_california_housing()` | 20,640 samples, 8 features |

---

## Limitations

- Linear SVM only (no RBF/polynomial kernels requiring QP solver)
- No sparse matrix support (no scipy.sparse)
- Manifold methods may be slow on large datasets
- Neural network limited to standard MLP architecture
