"""
matplotlib compatibility layer for OfflinAi.
Routes all plotting through plotly for high-quality interactive charts.
Supports the common matplotlib.pyplot API surface.
"""

__version__ = "3.9.0-offlinai"
__file__ = __file__

_backend = "offlinai_plotly"

def use(backend, **kwargs):
    """Accepted but ignored — always uses plotly backend."""
    global _backend
    _backend = backend

def get_backend():
    return _backend
