"""mpl_toolkits.axisartist.axislines — axes with custom axis lines."""

from matplotlib.axes._axes import Axes as _Axes


class Axes(_Axes):
    name = 'axisartist.Axes'
    class AxisDict(dict):
        def __init__(self, axes):
            super().__init__()
            self._axes = axes

class SubplotZero(Axes):
    name = 'axisartist.SubplotZero'

class Subplot(Axes):
    pass

class AxesZero(SubplotZero):
    pass
