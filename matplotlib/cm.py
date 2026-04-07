"""matplotlib.cm (colormap) compatibility."""

def get_cmap(name='viridis'):
    return name

class ScalarMappable:
    def __init__(self, norm=None, cmap=None):
        self.norm = norm
        self.cmap = cmap
