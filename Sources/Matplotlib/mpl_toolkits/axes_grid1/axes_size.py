"""mpl_toolkits.axes_grid1.axes_size — size helpers."""

from mpl_toolkits.axes_grid1.axes_divider import Size

Fixed = Size.Fixed
Scaled = Size.Scaled
AxesX = Size.AxesX
AxesY = Size.AxesY
Fraction = Size.Fraction
Padded = Size.Padded
from_any = Size.from_any

class MaxExtent:
    def __init__(self, artist_list, w_or_h):
        pass

class MaxWidth(MaxExtent):
    def __init__(self, artist_list):
        super().__init__(artist_list, 'width')

class MaxHeight(MaxExtent):
    def __init__(self, artist_list):
        super().__init__(artist_list, 'height')

class SizeFromFunc:
    def __init__(self, func):
        self._func = func
