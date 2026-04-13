"""matplotlib.ticker compatibility — stubs."""

class Locator:
    pass

class MaxNLocator(Locator):
    def __init__(self, nbins=10, **kwargs):
        self.nbins = nbins

class MultipleLocator(Locator):
    def __init__(self, base=1.0):
        self.base = base

class FuncFormatter:
    def __init__(self, func):
        self.func = func

class PercentFormatter:
    def __init__(self, xmax=100):
        self.xmax = xmax
