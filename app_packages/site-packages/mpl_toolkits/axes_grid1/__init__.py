"""mpl_toolkits.axes_grid1 — axes grid toolkit."""

from mpl_toolkits.axes_grid1.axes_divider import make_axes_locatable, Divider, SubplotDivider
from mpl_toolkits.axes_grid1.axes_grid import Grid, ImageGrid
from mpl_toolkits.axes_grid1.inset_locator import (
    inset_axes, zoomed_inset_axes, mark_inset, InsetPosition
)
from mpl_toolkits.axes_grid1.anchored_artists import AnchoredSizeBar, AnchoredDirectionArrows
from mpl_toolkits.axes_grid1.parasite_axes import HostAxes, ParasiteAxes

# Legacy alias
AxesGrid = ImageGrid
