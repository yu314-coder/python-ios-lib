# torch_ios: moderngl stub for iOS.
#
# moderngl is a Python binding around OpenGL ES / desktop GL. iOS
# dropped OpenGL in favor of Metal, so moderngl has no iOS build.
# Manim's opengl renderer modules import moderngl at load time but
# never actually use it — iOS manim renders via Cairo, not OpenGL.
# This stub provides the class names / attributes manim's imports
# reference; instantiating any of them raises NotImplementedError.

__version__ = "5.12.0+torch_ios_stub"


class _NotImplementedStub:
    def __init__(self, *args, **kwargs):
        raise NotImplementedError(
            "moderngl: iOS has no OpenGL. This is a stub for manim's "
            "opengl_mobject/shader imports. Use the cairo renderer."
        )
    def __class_getitem__(cls, _item):
        return cls


# Class names referenced by manim's opengl imports
class Context(_NotImplementedStub): pass
class Program(_NotImplementedStub): pass
class Framebuffer(_NotImplementedStub): pass
class Texture(_NotImplementedStub): pass
class Buffer(_NotImplementedStub): pass
class VertexArray(_NotImplementedStub): pass
class Renderbuffer(_NotImplementedStub): pass
class Uniform(_NotImplementedStub): pass
class Attribute(_NotImplementedStub): pass
class Scope(_NotImplementedStub): pass
class Query(_NotImplementedStub): pass
class Sampler(_NotImplementedStub): pass
class ComputeShader(_NotImplementedStub): pass
class TextureArray(_NotImplementedStub): pass
class Texture3D(_NotImplementedStub): pass
class TextureCube(_NotImplementedStub): pass
class Error(Exception): pass


# GL draw-mode constants
POINTS = 0
LINES = 1
LINE_LOOP = 2
LINE_STRIP = 3
TRIANGLES = 4
TRIANGLE_STRIP = 5
TRIANGLE_FAN = 6
LINES_ADJACENCY = 10
LINE_STRIP_ADJACENCY = 11
TRIANGLES_ADJACENCY = 12
TRIANGLE_STRIP_ADJACENCY = 13

# Blend / usage
BLEND = 3042
DEPTH_TEST = 2929
CULL_FACE = 2884
NEAREST = 9728
LINEAR = 9729
CLAMP_TO_EDGE = 33071
REPEAT = 10497


def create_context(*args, **kwargs):
    raise NotImplementedError("moderngl.create_context: iOS has no OpenGL")


def create_standalone_context(*args, **kwargs):
    raise NotImplementedError("moderngl.create_standalone_context: iOS has no OpenGL")


def __getattr__(name):
    # Return a permissive callable/class for any unknown attribute so that
    # `moderngl.Whatever(...)` at class-definition/import time doesn't crash
    # until actually instantiated.
    return _NotImplementedStub
