"""mpl_toolkits.axes_grid1.mpl_axes — wrapper axes."""

from matplotlib.axes._axes import Axes

class Axes(Axes):
    class AxisDict(dict):
        def __init__(self, axes):
            super().__init__()
            self._axes = axes
