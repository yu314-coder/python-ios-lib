"""matplotlib.patches compatibility — stubs."""

class Patch:
    def __init__(self, **kwargs):
        self.kwargs = kwargs

class Rectangle(Patch):
    def __init__(self, xy, width, height, **kwargs):
        super().__init__(**kwargs)

class Circle(Patch):
    def __init__(self, center, radius, **kwargs):
        super().__init__(**kwargs)

class FancyArrowPatch(Patch):
    pass
