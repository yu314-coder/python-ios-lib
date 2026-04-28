"""
mpl_toolkits.mplot3d compatibility shim for OfflinAi.
Routes 3D plotting through plotly via the matplotlib.pyplot compatibility layer.

Supports all common import patterns:
    from mpl_toolkits.mplot3d import Axes3D
    from mpl_toolkits.mplot3d import axes3d
    from mpl_toolkits.mplot3d import art3d, proj3d
    from mpl_toolkits.mplot3d import Axes
    from mpl_toolkits.mplot3d.axes3d import Axes3D
    import mpl_toolkits.mplot3d.projection  # no-op
"""

import sys as _sys


class Axes3D:
    """Compatibility shim for mpl_toolkits.mplot3d.Axes3D.

    In the OfflinAi plotly backend, 3D is handled by _Axes with _is_3d=True.
    This class exists so that `from mpl_toolkits.mplot3d import Axes3D`
    works and `Axes3D(fig)` returns a usable 3D axes object.
    """
    def __new__(cls, fig=None, *args, **kwargs):
        try:
            from matplotlib import pyplot as plt
        except ImportError:
            return object.__new__(cls)
        if fig is None:
            fig = plt.gcf()
        ax = fig.add_subplot(111, projection='3d')
        return ax

    def __init_subclass__(cls, **kwargs):
        pass


# Axes is an alias for Axes3D (some code does `from mpl_toolkits.mplot3d import Axes`)
Axes = Axes3D


# ── art3d module stub ──
class _Poly3DCollection:
    def __init__(self, *a, **kw): pass
    def set_alpha(self, a): pass
    def set_facecolor(self, c): pass
    def set_edgecolor(self, c): pass
    def set_zsort(self, s): pass
    def set_sort_zpos(self, z): pass

class _Line3DCollection:
    def __init__(self, *a, **kw): pass
    def set_color(self, c): pass

class _Art3DModule:
    Poly3DCollection = _Poly3DCollection
    Line3DCollection = _Line3DCollection
    def __getattr__(self, name):
        return lambda *a, **kw: None

art3d = _Art3DModule()


# ── proj3d module stub ──
class _Proj3DModule:
    @staticmethod
    def proj_transform(x, y, z, M=None):
        return (x, y, z)
    @staticmethod
    def world_transformation(xmin, xmax, ymin, ymax, zmin, zmax, pb_aspect=None):
        import numpy as np
        return np.eye(4)
    def __getattr__(self, name):
        return lambda *a, **kw: None

proj3d = _Proj3DModule()


# ── axis3d module stub ──
class _Axis3DModule:
    class Axis:
        def __init__(self, *a, **kw): pass
    class XAxis(Axis): pass
    class YAxis(Axis): pass
    class ZAxis(Axis): pass
    def __getattr__(self, name):
        return lambda *a, **kw: None

axis3d = _Axis3DModule()


# ── axes3d sub-module (for `from mpl_toolkits.mplot3d.axes3d import Axes3D`) ──
class _Axes3DModule:
    Axes3D = Axes3D
    Axes = Axes3D
    def __getattr__(self, name):
        return Axes3D

axes3d = _Axes3DModule()


# ── projection stub ──
class _ProjectionModule:
    def __getattr__(self, name):
        return lambda *a, **kw: None

projection = _ProjectionModule()


# Register sub-modules in sys.modules so `import mpl_toolkits.mplot3d.axes3d` works
_this = _sys.modules[__name__]
_sys.modules['mpl_toolkits.mplot3d.art3d'] = art3d
_sys.modules['mpl_toolkits.mplot3d.proj3d'] = proj3d
_sys.modules['mpl_toolkits.mplot3d.axis3d'] = axis3d
_sys.modules['mpl_toolkits.mplot3d.axes3d'] = axes3d
_sys.modules['mpl_toolkits.mplot3d.projection'] = projection
