"""Metrics: accuracy, MSE, MAE, R², confusion matrix, classification report."""
import numpy as np


def accuracy_score(y_true, y_pred):
    return np.mean(np.asarray(y_true) == np.asarray(y_pred))


def mean_squared_error(y_true, y_pred):
    return float(np.mean((np.asarray(y_true, dtype=float) - np.asarray(y_pred, dtype=float)) ** 2))


def mean_absolute_error(y_true, y_pred):
    return float(np.mean(np.abs(np.asarray(y_true, dtype=float) - np.asarray(y_pred, dtype=float))))


def r2_score(y_true, y_pred):
    y_true = np.asarray(y_true, dtype=float)
    y_pred = np.asarray(y_pred, dtype=float)
    ss_res = np.sum((y_true - y_pred) ** 2)
    ss_tot = np.sum((y_true - np.mean(y_true)) ** 2)
    return 1.0 - ss_res / max(ss_tot, 1e-15)


def confusion_matrix(y_true, y_pred, labels=None):
    y_true, y_pred = np.asarray(y_true), np.asarray(y_pred)
    if labels is None:
        labels = np.unique(np.concatenate([y_true, y_pred]))
    n = len(labels)
    label_to_idx = {l: i for i, l in enumerate(labels)}
    cm = np.zeros((n, n), dtype=int)
    for t, p in zip(y_true, y_pred):
        if t in label_to_idx and p in label_to_idx:
            cm[label_to_idx[t], label_to_idx[p]] += 1
    return cm


def classification_report(y_true, y_pred, labels=None, output_dict=False):
    y_true, y_pred = np.asarray(y_true), np.asarray(y_pred)
    if labels is None:
        labels = np.unique(np.concatenate([y_true, y_pred]))
    report = {}
    for label in labels:
        tp = np.sum((y_true == label) & (y_pred == label))
        fp = np.sum((y_true != label) & (y_pred == label))
        fn = np.sum((y_true == label) & (y_pred != label))
        precision = tp / max(tp + fp, 1)
        recall = tp / max(tp + fn, 1)
        f1 = 2 * precision * recall / max(precision + recall, 1e-15)
        support = int(np.sum(y_true == label))
        report[str(label)] = {'precision': precision, 'recall': recall, 'f1-score': f1, 'support': support}
    acc = accuracy_score(y_true, y_pred)
    report['accuracy'] = acc
    if output_dict:
        return report
    lines = [f"{'':>12} {'precision':>10} {'recall':>10} {'f1-score':>10} {'support':>10}"]
    lines.append("")
    for label in labels:
        r = report[str(label)]
        lines.append(f"{str(label):>12} {r['precision']:>10.2f} {r['recall']:>10.2f} {r['f1-score']:>10.2f} {r['support']:>10d}")
    lines.append("")
    lines.append(f"{'accuracy':>12} {'':>10} {'':>10} {acc:>10.2f} {len(y_true):>10d}")
    return "\n".join(lines)


def mean_squared_log_error(y_true, y_pred):
    y_true = np.asarray(y_true, dtype=float)
    y_pred = np.asarray(y_pred, dtype=float)
    return float(np.mean((np.log1p(y_true) - np.log1p(y_pred)) ** 2))


def precision_score(y_true, y_pred, average='binary', pos_label=1):
    y_true, y_pred = np.asarray(y_true), np.asarray(y_pred)
    if average == 'binary':
        tp = np.sum((y_true == pos_label) & (y_pred == pos_label))
        fp = np.sum((y_true != pos_label) & (y_pred == pos_label))
        return tp / max(tp + fp, 1)
    labels = np.unique(np.concatenate([y_true, y_pred]))
    precisions = []
    supports = []
    for label in labels:
        tp = np.sum((y_true == label) & (y_pred == label))
        fp = np.sum((y_true != label) & (y_pred == label))
        precisions.append(tp / max(tp + fp, 1))
        supports.append(np.sum(y_true == label))
    if average == 'macro':
        return float(np.mean(precisions))
    elif average == 'weighted':
        return float(np.average(precisions, weights=supports))
    return np.array(precisions)


def recall_score(y_true, y_pred, average='binary', pos_label=1):
    y_true, y_pred = np.asarray(y_true), np.asarray(y_pred)
    if average == 'binary':
        tp = np.sum((y_true == pos_label) & (y_pred == pos_label))
        fn = np.sum((y_true == pos_label) & (y_pred != pos_label))
        return tp / max(tp + fn, 1)
    labels = np.unique(np.concatenate([y_true, y_pred]))
    recalls = []
    supports = []
    for label in labels:
        tp = np.sum((y_true == label) & (y_pred == label))
        fn = np.sum((y_true == label) & (y_pred != label))
        recalls.append(tp / max(tp + fn, 1))
        supports.append(np.sum(y_true == label))
    if average == 'macro':
        return float(np.mean(recalls))
    elif average == 'weighted':
        return float(np.average(recalls, weights=supports))
    return np.array(recalls)


def f1_score(y_true, y_pred, average='binary', pos_label=1):
    p = precision_score(y_true, y_pred, average=average, pos_label=pos_label)
    r = recall_score(y_true, y_pred, average=average, pos_label=pos_label)
    if isinstance(p, np.ndarray):
        return 2 * p * r / np.maximum(p + r, 1e-15)
    return float(2 * p * r / max(p + r, 1e-15))


def roc_auc_score(y_true, y_score):
    """Area under ROC curve using trapezoidal rule. Binary classification only."""
    y_true = np.asarray(y_true)
    y_score = np.asarray(y_score, dtype=float)
    # Sort by decreasing score
    desc_idx = np.argsort(y_score)[::-1]
    y_true_sorted = y_true[desc_idx]
    y_score_sorted = y_score[desc_idx]
    # Compute distinct thresholds
    distinct_idx = np.where(np.diff(y_score_sorted))[0]
    threshold_idx = np.concatenate([distinct_idx, [len(y_true) - 1]])
    tps = np.cumsum(y_true_sorted)[threshold_idx]
    fps = (threshold_idx + 1) - tps
    total_pos = np.sum(y_true)
    total_neg = len(y_true) - total_pos
    if total_pos == 0 or total_neg == 0:
        return 0.5
    tpr = tps / total_pos
    fpr = fps / total_neg
    # Prepend origin
    tpr = np.concatenate([[0], tpr])
    fpr = np.concatenate([[0], fpr])
    # Trapezoidal rule
    return float(np.trapz(tpr, fpr))


def silhouette_score(X, labels):
    """Simplified silhouette score."""
    X = np.asarray(X, dtype=float)
    labels = np.asarray(labels)
    n = len(X)
    scores = np.zeros(n)
    unique_labels = np.unique(labels)
    if len(unique_labels) < 2:
        return 0.0
    for i in range(n):
        same = labels == labels[i]
        same[i] = False
        if same.sum() == 0:
            scores[i] = 0
            continue
        a = np.mean(np.sqrt(np.sum((X[same] - X[i]) ** 2, axis=1)))
        b = np.inf
        for l in unique_labels:
            if l == labels[i]:
                continue
            other = labels == l
            if other.sum() > 0:
                d = np.mean(np.sqrt(np.sum((X[other] - X[i]) ** 2, axis=1)))
                b = min(b, d)
        scores[i] = (b - a) / max(a, b, 1e-15)
    return float(np.mean(scores))
