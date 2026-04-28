# torch_ios: moderngl_window stub (manim.renderer.opengl_renderer_window imports it
# but we never instantiate on iOS — cairo is the renderer)
class _Stub:
    def __init__(self, *a, **k):
        raise NotImplementedError("moderngl_window: iOS uses cairo renderer")

def __getattr__(name):
    return _Stub
