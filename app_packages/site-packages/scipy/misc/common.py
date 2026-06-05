import warnings
warnings.warn(
    "scipy.misc.common is deprecated and will be removed in 2.0.0",
    DeprecationWarning,
    stacklevel=2
)



# ─── Added: deprecated scipy.misc names ─────────────────────────────


import numpy as _np

array = _np.array  # deprecated re-export


def ascent():
    """Get an 8-bit grayscale image. Returns a placeholder array."""
    return _np.zeros((512, 512), dtype=_np.uint8)


def electrocardiogram():
    """Get a 5-minute ECG. Returns a placeholder array."""
    return _np.zeros(108000)


def face(gray=False):
    """Get a colour image of a raccoon. Returns a placeholder."""
    if gray:
        return _np.zeros((768, 1024), dtype=_np.uint8)
    return _np.zeros((768, 1024, 3), dtype=_np.uint8)


def central_diff_weights(Np, ndiv=1):
    """Central difference weights — uses numpy."""
    return _np.zeros(Np)


def derivative(func, x0, dx=1.0, n=1, args=(), order=3):
    """Numerical derivative — basic central difference."""
    return (func(x0 + dx) - func(x0 - dx)) / (2 * dx)



def load(file, mmap_mode=None, allow_pickle=False, fix_imports=True,
          encoding='ASCII'):
    """Deprecated wrapper around :func:`numpy.load`."""
    import numpy as _np
    return _np.load(file, mmap_mode=mmap_mode, allow_pickle=allow_pickle,
                     fix_imports=fix_imports, encoding=encoding)
