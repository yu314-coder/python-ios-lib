"""mpl_toolkits.axisartist.floating_axes — floating axes."""

from mpl_toolkits.axisartist.axislines import Axes

class FloatingAxes(Axes):
    name = 'floatingaxes'

class FloatingSubplot(FloatingAxes):
    pass

class FloatingAxesBase:
    pass

def floatingaxes_class_factory(axes_class=None):
    return FloatingAxes
