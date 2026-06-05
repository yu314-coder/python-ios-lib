import warnings
warnings.warn(
    "scipy.misc is deprecated and will be removed in 2.0.0",
    DeprecationWarning,
    stacklevel=2
)



# ─── Added: deprecated test/dataset hooks ───────────────────────────


dataset_methods = []  # populated by `_init_datasets`


def test(*args, **kwargs):
    """Run scipy.misc tests — stub."""
    return None
