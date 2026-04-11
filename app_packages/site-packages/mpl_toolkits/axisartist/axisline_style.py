"""mpl_toolkits.axisartist.axisline_style — axis line styles."""

class AxislineStyle:
    class _Base:
        def __init__(self, **kwargs): pass
    class SimpleArrow(_Base): pass
    class FilledArrow(_Base): pass
