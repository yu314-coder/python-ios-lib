"""mpl_toolkits.axisartist.grid_finder — grid finder."""

import numpy as _np

class GridFinder:
    def __init__(self, transform, extreme_finder=None, grid_locator1=None,
                 grid_locator2=None, tick_formatter1=None, tick_formatter2=None):
        self.transform = transform

class MaxNLocator:
    def __init__(self, nbins=10, steps=None):
        self.nbins = nbins

class FixedLocator:
    def __init__(self, locs):
        self.locs = locs

class FormatterPrettyPrint:
    def __call__(self, direction, factor, values):
        return [f'{v:g}' for v in values]

class DictFormatter:
    def __init__(self, mapping, formatter=None):
        self._mapping = mapping
    def __call__(self, direction, factor, values):
        return [self._mapping.get(v, str(v)) for v in values]

class ExtremeFinderSimple:
    def __init__(self, nx, ny):
        self.nx = nx
        self.ny = ny
