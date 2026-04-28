"""mpl_toolkits.axes_grid1.axes_grid — grid of axes."""


class Grid:
    def __init__(self, fig, rect, nrows_ncols, ngrids=None, direction='row',
                 axes_pad=0.02, *, share_all=False, share_x=True, share_y=True,
                 label_mode='L', axes_class=None, aspect=False):
        self.nrows, self.ncols = nrows_ncols
        self._axes = []
        self.axes_pad = axes_pad

    def __getitem__(self, i):
        return self._axes[i] if i < len(self._axes) else None

    def __len__(self):
        return len(self._axes)

    def __iter__(self):
        return iter(self._axes)

    @property
    def axes_all(self):
        return self._axes

    @property
    def axes_column(self):
        return [[]]

    @property
    def axes_row(self):
        return [[]]


class ImageGrid(Grid):
    def __init__(self, fig, rect, nrows_ncols, ngrids=None, direction='row',
                 axes_pad=0.02, *, share_all=False, aspect=True,
                 label_mode='L', cbar_mode=None, cbar_location='right',
                 cbar_pad=None, cbar_size='5%', cbar_set_cax=True,
                 axes_class=None):
        super().__init__(fig, rect, nrows_ncols, ngrids, direction, axes_pad)
        self.cbar_mode = cbar_mode
        self.cbar_axes = []


AxesGrid = ImageGrid
