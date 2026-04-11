"""mpl_toolkits.axisartist.axis_artist — axis artist."""

from matplotlib.artist import Artist

class AxisArtist(Artist):
    def __init__(self, axes, helper, offset=None, axis_direction='bottom'):
        super().__init__()
        self.axes = axes
        self.helper = helper
        self.axis_direction = axis_direction
        self.major_ticklabels = TickLabels()
        self.minor_ticklabels = TickLabels()
        self.label = AxisLabel()
        self.major_ticks = Ticks(10)
        self.minor_ticks = Ticks(5)
        self.line = AxisLine()

    def set_visible(self, b): pass
    def toggle(self, all=None, ticks=None, ticklabels=None, label=None): pass

class AxisLabel:
    def __init__(self): pass
    def set_text(self, s): pass
    def set_visible(self, b): pass

class TickLabels:
    def __init__(self): pass
    def set_visible(self, b): pass

class Ticks:
    def __init__(self, ticksize):
        self._ticksize = ticksize
    def set_ticksize(self, s): self._ticksize = s
    def set_visible(self, b): pass

class AxisLine:
    def __init__(self): pass
    def set_visible(self, b): pass
