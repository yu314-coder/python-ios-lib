"""mpl_toolkits.axes_grid1.parasite_axes — parasite axes."""

from matplotlib.axes._axes import Axes


class ParasiteAxesBase:
    pass


class ParasiteAxes(Axes, ParasiteAxesBase):
    name = 'parasite_axes'

    def __init__(self, parent_axes, **kwargs):
        super().__init__(getattr(parent_axes, 'figure', None), **kwargs)
        self._parent_axes = parent_axes


class HostAxesBase:
    def __init__(self):
        self.parasites = []

    def get_aux_axes(self, tr=None, viewlim_mode=None, axes_class=None):
        return ParasiteAxes(self)

    def twin(self, aux_trans=None, axes_class=None):
        return ParasiteAxes(self)

    def twinx(self):
        return ParasiteAxes(self)

    def twiny(self):
        return ParasiteAxes(self)


class HostAxes(Axes, HostAxesBase):
    def __init__(self, *args, **kwargs):
        Axes.__init__(self, *args, **kwargs)
        HostAxesBase.__init__(self)


def host_subplot_class_factory(axes_class=None):
    return HostAxes

def host_axes_class_factory(axes_class=None):
    return HostAxes

def host_subplot(*args, **kwargs):
    return HostAxes(*args, **kwargs)

def host_axes(*args, **kwargs):
    return HostAxes(*args, **kwargs)
