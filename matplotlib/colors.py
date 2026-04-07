"""matplotlib.colors compatibility."""

def to_rgba(c, alpha=None):
    if isinstance(c, str):
        _named = {'red': (1,0,0,1), 'blue': (0,0,1,1), 'green': (0,0.5,0,1),
                  'black': (0,0,0,1), 'white': (1,1,1,1), 'yellow': (1,1,0,1),
                  'cyan': (0,1,1,1), 'magenta': (1,0,1,1), 'orange': (1,0.65,0,1)}
        rgba = _named.get(c.lower(), (0,0,0,1))
    elif isinstance(c, (tuple, list)):
        rgba = tuple(c) + (1,) * (4 - len(c))
    else:
        rgba = (0, 0, 0, 1)
    if alpha is not None:
        rgba = rgba[:3] + (alpha,)
    return rgba

class Normalize:
    def __init__(self, vmin=0, vmax=1):
        self.vmin = vmin
        self.vmax = vmax
    def __call__(self, x):
        return (x - self.vmin) / max(self.vmax - self.vmin, 1e-10)

class LogNorm(Normalize):
    pass

class ListedColormap:
    def __init__(self, colors, name='custom'):
        self.colors = colors
        self.name = name
    def __call__(self, x):
        idx = int(x * (len(self.colors) - 1))
        return self.colors[max(0, min(idx, len(self.colors) - 1))]
