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
