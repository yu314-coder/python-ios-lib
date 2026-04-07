"""matplotlib.cm (colormap) compatibility with plotly colorscale mapping."""

import numpy as _np

# Mapping of matplotlib colormap names to plotly equivalents
_CMAP_TO_PLOTLY = {
    'viridis': 'Viridis',
    'plasma': 'Plasma',
    'inferno': 'Inferno',
    'magma': 'Magma',
    'cividis': 'Cividis',
    'hot': 'Hot',
    'cool': 'Blues',
    'coolwarm': 'RdBu',
    'jet': 'Jet',
    'rainbow': 'Rainbow',
    'turbo': 'Turbo',
    'gray': 'Greys',
    'grey': 'Greys',
    'bone': 'Greys',
    'copper': 'Oranges',
    'spring': 'YlGn',
    'summer': 'YlGn',
    'autumn': 'YlOrRd',
    'winter': 'Blues',
    'RdYlGn': 'RdYlGn',
    'RdBu': 'RdBu',
    'Spectral': 'Spectral',
    'YlGnBu': 'YlGnBu',
    'YlOrRd': 'YlOrRd',
    'PuBu': 'PuBu',
    'BuGn': 'BuGn',
    'Greens': 'Greens',
    'Blues': 'Blues',
    'Reds': 'Reds',
    'Oranges': 'Oranges',
    'Purples': 'Purples',
    'PiYG': 'PiYG',
    'PRGn': 'PRGn',
    'BrBG': 'BrBG',
    'Set1': 'Set1',
    'Set2': 'Set2',
    'Set3': 'Set3',
    'Paired': 'Paired',
    'tab10': 'D3',
    'tab20': 'D3',
    'hsv': 'HSV',
    'twilight': 'IceFire',
    'twilight_shifted': 'IceFire',
}

# Simple approximate RGB stops for common colormaps (for __call__ support)
_CMAP_STOPS = {
    'viridis':  [(68,1,84), (59,82,139), (33,145,140), (94,201,98), (253,231,37)],
    'plasma':   [(13,8,135), (126,3,168), (204,71,120), (248,149,64), (240,249,33)],
    'inferno':  [(0,0,4), (87,16,110), (188,55,84), (249,142,9), (252,255,164)],
    'magma':    [(0,0,4), (81,18,124), (183,55,121), (252,137,97), (252,253,191)],
    'hot':      [(10,0,0), (255,0,0), (255,165,0), (255,255,0), (255,255,255)],
    'jet':      [(0,0,131), (0,60,255), (0,255,255), (255,255,0), (255,0,0), (128,0,0)],
    'coolwarm': [(59,76,192), (141,176,254), (245,245,245), (254,169,132), (180,4,38)],
    'gray':     [(0,0,0), (128,128,128), (255,255,255)],
    'Blues':    [(247,251,255), (107,174,214), (8,48,107)],
    'Reds':    [(255,245,240), (252,146,114), (103,0,13)],
}


class _Colormap:
    """A callable colormap that maps scalar values [0,1] to RGBA tuples."""
    def __init__(self, name):
        self.name = name
        self._plotly_name = _CMAP_TO_PLOTLY.get(name, name)
        self._stops = _CMAP_STOPS.get(name, [(68,1,84), (33,145,140), (253,231,37)])

    def __call__(self, value):
        """Map a scalar or array of scalars in [0,1] to RGBA tuples."""
        if isinstance(value, _np.ndarray):
            return _np.array([self._single(float(v)) for v in value.ravel()]).reshape(value.shape + (4,))
        if hasattr(value, '__iter__') and not isinstance(value, str):
            return [self._single(float(v)) for v in value]
        return self._single(float(value))

    def _single(self, v):
        """Map a single float in [0,1] to (r, g, b, a) with values in [0,1]."""
        v = max(0.0, min(1.0, v))
        stops = self._stops
        n = len(stops) - 1
        idx = v * n
        i = min(int(idx), n - 1)
        t = idx - i
        r = (stops[i][0] * (1 - t) + stops[i+1][0] * t) / 255.0
        g = (stops[i][1] * (1 - t) + stops[i+1][1] * t) / 255.0
        b = (stops[i][2] * (1 - t) + stops[i+1][2] * t) / 255.0
        return (r, g, b, 1.0)

    @property
    def plotly_colorscale(self):
        return self._plotly_name

    def __str__(self):
        return self.name

    def __repr__(self):
        return f"_Colormap('{self.name}')"


def get_cmap(name='viridis'):
    """Return a colormap object by name."""
    if isinstance(name, _Colormap):
        return name
    return _Colormap(str(name))


def to_plotly(name):
    """Convert a matplotlib colormap name to its plotly equivalent string."""
    if isinstance(name, _Colormap):
        return name.plotly_colorscale
    return _CMAP_TO_PLOTLY.get(str(name), str(name))


class ScalarMappable:
    def __init__(self, norm=None, cmap=None):
        self.norm = norm
        self.cmap = get_cmap(cmap) if isinstance(cmap, str) else cmap
