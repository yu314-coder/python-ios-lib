"""mpl_toolkits.axes_grid1.anchored_artists — anchored artist helpers."""

from matplotlib.offsetbox import AnchoredOffsetbox


class AnchoredSizeBar(AnchoredOffsetbox):
    def __init__(self, transform, size, label, loc, pad=0.1, borderpad=0.1,
                 sep=2, frameon=True, size_vertical=0, color='black',
                 label_top=False, fontproperties=None, fill_bar=None, **kwargs):
        super().__init__(loc, pad=pad, borderpad=borderpad)
        self.size = size
        self.label = label


class AnchoredDirectionArrows(AnchoredOffsetbox):
    def __init__(self, transform, label_x, label_y, length=0.15,
                 fontsize=0.08, loc='upper left', angle=0, aspect_ratio=1,
                 pad=0.4, borderpad=0.4, frameon=False, color='w',
                 alpha=1, sep_x=0.01, sep_y=0, fontproperties=None,
                 back_length=0.15, head_width=10, head_length=15,
                 tail_width=2, text_props=None, arrow_props=None, **kwargs):
        super().__init__(loc, pad=pad, borderpad=borderpad)


class AnchoredEllipse(AnchoredOffsetbox):
    def __init__(self, transform, width, height, angle, loc, pad=0.1,
                 borderpad=0.1, prop=None, frameon=True, **kwargs):
        super().__init__(loc, pad=pad, borderpad=borderpad)


class AnchoredAuxTransformBox(AnchoredOffsetbox):
    def __init__(self, transform, loc, pad=0.4, borderpad=0.5, prop=None,
                 frameon=True, **kwargs):
        super().__init__(loc, pad=pad, borderpad=borderpad)
