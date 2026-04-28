"""mpl_toolkits.axes_grid1.axes_divider — axes divider."""


class Divider:
    def __init__(self, fig, pos, horizontal, vertical, aspect=None, anchor='C'):
        self._fig = fig
        self._pos = pos

    def new_locator(self, nx, ny, nx1=None, ny1=None):
        return lambda ax, renderer: None

    def append_size(self, position, size):
        pass


class SubplotDivider(Divider):
    def __init__(self, fig, *args, horizontal=None, vertical=None, aspect=None, anchor='C'):
        super().__init__(fig, None, horizontal or [], vertical or [], aspect, anchor)


class AxesDivider:
    def __init__(self, axes):
        self._axes = axes

    def append_axes(self, position, size, pad=None, add_to_figure=True, **kwargs):
        return self._axes

    def new_horizontal(self, size, pad=None, pack_start=False, **kwargs):
        return None

    def new_vertical(self, size, pad=None, pack_start=False, **kwargs):
        return None


def make_axes_locatable(axes):
    return AxesDivider(axes)


class Size:
    class Fixed:
        def __init__(self, fixed_size, fraction=None):
            self.fixed_size = fixed_size

    class Scaled:
        def __init__(self, scalable_size):
            self.scalable_size = scalable_size

    class AxesX:
        def __init__(self, axes, aspect=1, ref_ax=None):
            pass

    class AxesY:
        def __init__(self, axes, aspect=1, ref_ax=None):
            pass

    class Fraction:
        def __init__(self, fraction, ref_size=None):
            self.fraction = fraction

    class Padded:
        def __init__(self, size, pad):
            pass

    @staticmethod
    def from_any(size, fraction_ref=None):
        if isinstance(size, (int, float)):
            return Size.Fixed(size)
        return Size.Fixed(0)
