"""mpl_toolkits.axes_grid1.inset_locator — inset axes utilities."""


class InsetPosition:
    def __init__(self, parent, lbwh):
        self.parent = parent
        self.lbwh = lbwh


def inset_axes(parent_axes, width, height, loc='upper right', bbox_to_anchor=None,
               bbox_transform=None, axes_class=None, axes_kwargs=None, borderpad=0.5):
    return parent_axes


def zoomed_inset_axes(parent_axes, zoom, loc='upper right', bbox_to_anchor=None,
                      bbox_transform=None, axes_class=None, axes_kwargs=None, borderpad=0.5):
    return parent_axes


def mark_inset(parent_axes, inset_axes, loc1, loc2, **kwargs):
    return (None, None)


class AnchoredLocatorBase:
    def __init__(self, bbox_to_anchor, offsetbox, loc, borderpad=0.5,
                 bbox_transform=None):
        pass


class AnchoredZoomLocator(AnchoredLocatorBase):
    def __init__(self, parent_axes, zoom, loc, borderpad=0.5, bbox_to_anchor=None,
                 bbox_transform=None):
        pass


class BboxPatch:
    def __init__(self, bbox, **kwargs):
        self.bbox = bbox


class BboxConnector:
    def __init__(self, bbox1, bbox2, loc1, loc2=None, **kwargs):
        pass


class BboxConnectorPatch:
    def __init__(self, bbox1, bbox2, loc1a, loc2a, loc1b=None, loc2b=None, **kwargs):
        pass
