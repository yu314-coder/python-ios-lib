"""mpl_toolkits.axisartist.angle_helper — angle utilities."""

import numpy as _np

class LocatorBase:
    pass

class LocatorDMS(LocatorBase):
    def __init__(self, den=4, include_last=True): pass

class LocatorHMS(LocatorBase):
    def __init__(self, den=4, include_last=True): pass

class LocatorD(LocatorBase):
    def __init__(self, nbins=8, include_last=True): pass

class LocatorH(LocatorBase):
    def __init__(self, nbins=8, include_last=True): pass

class FormatterDMS:
    def __call__(self, direction, factor, values):
        return [f'{v}°' for v in values]

class FormatterHMS:
    def __call__(self, direction, factor, values):
        return [f'{v}h' for v in values]

def select_step_degree(dv):
    return 15.0

def select_step_hour(dv):
    return 1.0

def select_step_sub(dv):
    return 1.0

def select_step(dv, factor, is_hour=False):
    return select_step_hour(dv) if is_hour else select_step_degree(dv)
