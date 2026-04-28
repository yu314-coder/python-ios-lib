"""mpl_toolkits.axisartist.grid_helper_curvelinear — curvelinear grid."""

from mpl_toolkits.axisartist.grid_finder import GridFinder

class GridHelperCurveLinear:
    def __init__(self, aux_trans, extreme_finder=None, grid_locator1=None,
                 grid_locator2=None, tick_formatter1=None, tick_formatter2=None):
        self.grid_finder = GridFinder(aux_trans, extreme_finder,
                                      grid_locator1, grid_locator2,
                                      tick_formatter1, tick_formatter2)

    def new_fixed_axis(self, loc, nth_coord=None, axis_direction=None,
                       offset=None, axes=None):
        return None

    def new_floating_axis(self, nth_coord, value, axes=None, axis_direction='bottom'):
        return None
