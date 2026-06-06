/*
 * cairo_metal_ext.c  --  pycairo-compatible CPython shim over the CairoMetal C API
 * ============================================================================
 * Exposes a FULL pycairo-compatible API surface, forwarding every call to the
 * GPU-backed cm_* C API declared in include/cairo_metal.h.  The goal is that
 *
 *     import cairo_metal as cairo
 *
 * is a drop-in for as much of the real pycairo class graph as the CairoMetal C
 * library actually backs (every method below calls exactly one cm_* function
 * that is declared in cairo_metal.h -- no invented symbols).
 *
 * Classes exposed:
 *   Matrix, Surface(base), ImageSurface, RecordingSurface,
 *   Pattern(base), SolidPattern, SurfacePattern, Gradient(base),
 *   LinearGradient, RadialGradient, MeshPattern,
 *   Region,
 *   FontFace(base), ToyFontFace, ScaledFont, FontOptions,
 *   Context,
 *   Error (exception), plus all cairo enums (Operator, Antialias, Content,
 *   Extend, Filter, Format, FillRule, LineCap, LineJoin, FontSlant,
 *   FontWeight, FontType, HintMetrics, HintStyle, SubpixelOrder, PatternType,
 *   PathDataType, RegionOverlap, SurfaceType, Status) and the cairo-flat
 *   constant aliases (cairo.FORMAT_ARGB32, cairo.OPERATOR_OVER, ...).
 *
 * This module is named `cairo_metal`, NOT `cairo`, so it can never shadow the
 * real pycairo install.
 *
 * PIXEL FORMAT: cairo FORMAT_ARGB32 on little-endian arm64 is premultiplied
 * B,G,R,A bytes in memory; the backing MTLTexture is BGRA8.  See cairo_metal.h.
 *
 * BUFFER MODEL: ImageSurface.create_for_data(data, ...) keeps a writable view
 * of the caller's buffer (e.g. manim's pixel_array); on flush()/get_data() we
 * commit the GPU frame and copy rendered premultiplied-BGRA pixels back into it.
 * ============================================================================
 */
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <structmember.h>
#include <string.h>
#include <math.h>
#include "cairo_metal.h"

/* ===========================================================================
 * Module-global state set up in PyInit_cairo_metal (exception type + the type
 * objects we need to reference from constructors / accessors).
 * =========================================================================== */
static PyObject *CairoError = NULL;          /* cairo_metal.Error            */

static PyTypeObject CMMatrixType;
static PyTypeObject CMSurfaceType;           /* base Surface                 */
static PyTypeObject CMImageSurfaceType;
static PyTypeObject CMRecordingSurfaceType;
static PyTypeObject CMPatternType;           /* base Pattern                 */
static PyTypeObject CMSolidPatternType;
static PyTypeObject CMSurfacePatternType;
static PyTypeObject CMRasterSourcePatternType;
static PyTypeObject CMGradientType;          /* base Gradient                */
static PyTypeObject CMLinearGradientType;
static PyTypeObject CMRadialGradientType;
static PyTypeObject CMMeshPatternType;
static PyTypeObject CMRegionType;
static PyTypeObject CMFontFaceType;          /* base FontFace                */
static PyTypeObject CMToyFontFaceType;
static PyTypeObject CMScaledFontType;
static PyTypeObject CMFontOptionsType;
static PyTypeObject CMContextType;
static PyTypeObject CMPathType;              /* copy_path() result (iterable)   */
static PyTypeObject CMPathIterType;          /* its iterator                    */

/* ---------------------------------------------------------------------------
 * Status -> exception.  cm_context_status / cm_last_status return a cm_status_t
 * (internal code); cm_to_cairo_status maps it to the cairo-numbered status and
 * cm_cairo_status_to_string gives the cairo message.  Raise cairo_metal.Error
 * with (message, status) like pycairo does.
 * --------------------------------------------------------------------------- */
static int
cm_raise_if_error(cm_status_t st)
{
    if (st == CM_STATUS_SUCCESS) return 0;
    int cairo_status = cm_to_cairo_status(st);
    const char *msg = cm_cairo_status_to_string(cairo_status);
    PyObject *exc = PyObject_CallFunction(CairoError, "si", msg, cairo_status);
    if (exc) { PyErr_SetObject(CairoError, exc); Py_DECREF(exc); }
    return -1;
}

/* Check a context's accumulated status and raise if it latched an error. */
static int
cm_check_ctx(cm_context_t *ctx)
{
    return cm_raise_if_error(cm_context_status(ctx));
}

/* tp_new for the ABSTRACT base types (Surface / Pattern / Gradient / FontFace).
 * pycairo makes these non-instantiable: `cairo.Surface()` raises
 * TypeError("The Surface type cannot be instantiated").  We install this as the
 * base's tp_new; the concrete subclasses set their own tp_new = PyType_GenericNew
 * (with a tp_init), so they construct normally and never reach this.  Using
 * tp->tp_name (after the module prefix) yields the exact "<Type> type cannot be
 * instantiated" wording for whichever base was called. */
static PyObject *
cm_abstract_new(PyTypeObject *type, PyObject *args, PyObject *kwds)
{
    (void)args; (void)kwds;
    const char *name = type->tp_name ? type->tp_name : "?";
    const char *dot  = strrchr(name, '.');   /* strip "cairo_metal." prefix */
    if (dot) name = dot + 1;
    PyErr_Format(PyExc_TypeError, "The %s type cannot be instantiated", name);
    return NULL;
}

/* ===========================================================================
 * Forward declarations for cross-referencing constructors.
 * =========================================================================== */
static PyObject *wrap_surface(cm_surface_t *surf, int owns);
static PyObject *wrap_pattern(cm_pattern_t *pat, int owns);
static PyObject *wrap_font_face(cm_font_face_t *ff, int owns);
static PyObject *matrix_from_cm(const cm_matrix_t *m);
static int       matrix_as_cm(PyObject *obj, cm_matrix_t *out);

/* ===========================================================================
 * Matrix  (cairo.Matrix(xx, yx, xy, yy, x0, y0) -- value type, full algebra)
 * =========================================================================== */
typedef struct {
    PyObject_HEAD
    cm_matrix_t m;
} CMMatrix;

static int
CMMatrix_init(CMMatrix *self, PyObject *args, PyObject *kwds)
{
    double xx = 1, yx = 0, xy = 0, yy = 1, x0 = 0, y0 = 0;
    if (PyTuple_GET_SIZE(args) != 0 &&
        !PyArg_ParseTuple(args, "dddddd", &xx, &yx, &xy, &yy, &x0, &y0))
        return -1;
    self->m.xx = xx; self->m.yx = yx; self->m.xy = xy;
    self->m.yy = yy; self->m.x0 = x0; self->m.y0 = y0;
    return 0;
}

/* classmethods: init_rotate (cairo.Matrix.init_rotate(radians)) */
static PyObject *
CMMatrix_init_rotate(PyObject *cls, PyObject *args)
{
    double radians;
    if (!PyArg_ParseTuple(args, "d", &radians)) return NULL;
    cm_matrix_t m;
    cm_matrix_init_rotate(&m, radians);
    return matrix_from_cm(&m);
}

static PyObject *
CMMatrix_repr(CMMatrix *self)
{
    return PyUnicode_FromFormat(
        "cairo_metal.Matrix(%R, %R, %R, %R, %R, %R)",
        PyFloat_FromDouble(self->m.xx), PyFloat_FromDouble(self->m.yx),
        PyFloat_FromDouble(self->m.xy), PyFloat_FromDouble(self->m.yy),
        PyFloat_FromDouble(self->m.x0), PyFloat_FromDouble(self->m.y0));
}

/* Sequence/tuple-style access: m[0]..m[5] -> xx,yx,xy,yy,x0,y0. */
static Py_ssize_t CMMatrix_len(CMMatrix *self) { (void)self; return 6; }
static PyObject *
CMMatrix_getitem(CMMatrix *self, Py_ssize_t i)
{
    const double *v = &self->m.xx;
    if (i < 0 || i >= 6) { PyErr_SetString(PyExc_IndexError, "Matrix index out of range"); return NULL; }
    return PyFloat_FromDouble(v[i]);
}
static PySequenceMethods CMMatrix_as_sequence = {
    .sq_length = (lenfunc)CMMatrix_len,
    .sq_item   = (ssizeargfunc)CMMatrix_getitem,
};

static PyObject *
CMMatrix_translate(CMMatrix *self, PyObject *args)
{
    double tx, ty;
    if (!PyArg_ParseTuple(args, "dd", &tx, &ty)) return NULL;
    cm_matrix_translate(&self->m, tx, ty);
    Py_RETURN_NONE;
}
static PyObject *
CMMatrix_scale(CMMatrix *self, PyObject *args)
{
    double sx, sy;
    if (!PyArg_ParseTuple(args, "dd", &sx, &sy)) return NULL;
    cm_matrix_scale(&self->m, sx, sy);
    Py_RETURN_NONE;
}
static PyObject *
CMMatrix_rotate(CMMatrix *self, PyObject *args)
{
    double r;
    if (!PyArg_ParseTuple(args, "d", &r)) return NULL;
    cm_matrix_rotate(&self->m, r);
    Py_RETURN_NONE;
}
static PyObject *
CMMatrix_invert(CMMatrix *self, PyObject *Py_UNUSED(i))
{
    if (cm_raise_if_error(cm_matrix_invert(&self->m)) < 0) return NULL;
    Py_RETURN_NONE;
}
/* multiply(other) -> Matrix : self FIRST then other (cairo_matrix_multiply). */
static PyObject *
CMMatrix_multiply(CMMatrix *self, PyObject *arg)
{
    cm_matrix_t b, r;
    if (matrix_as_cm(arg, &b) < 0) return NULL;
    cm_matrix_multiply(&r, &self->m, &b);
    return matrix_from_cm(&r);
}
/* operator * : a * b == cairo_matrix_multiply(a, b). */
static PyObject *
CMMatrix_mul(PyObject *a, PyObject *b)
{
    cm_matrix_t ma, mb, r;
    if (matrix_as_cm(a, &ma) < 0 || matrix_as_cm(b, &mb) < 0) {
        PyErr_Clear();
        Py_RETURN_NOTIMPLEMENTED;
    }
    cm_matrix_multiply(&r, &ma, &mb);
    return matrix_from_cm(&r);
}
static PyObject *
CMMatrix_transform_point(CMMatrix *self, PyObject *args)
{
    double x, y;
    if (!PyArg_ParseTuple(args, "dd", &x, &y)) return NULL;
    cm_matrix_transform_point(&self->m, &x, &y);
    return Py_BuildValue("(dd)", x, y);
}
static PyObject *
CMMatrix_transform_distance(CMMatrix *self, PyObject *args)
{
    double dx, dy;
    if (!PyArg_ParseTuple(args, "dd", &dx, &dy)) return NULL;
    cm_matrix_transform_distance(&self->m, &dx, &dy);
    return Py_BuildValue("(dd)", dx, dy);
}
/* as_tuple() -> (xx,yx,xy,yy,x0,y0) like pycairo. */
static PyObject *
CMMatrix_as_tuple(CMMatrix *self, PyObject *Py_UNUSED(i))
{
    return Py_BuildValue("(dddddd)", self->m.xx, self->m.yx, self->m.xy,
                         self->m.yy, self->m.x0, self->m.y0);
}

static PyObject *
CMMatrix_richcompare(PyObject *a, PyObject *b, int op)
{
    if ((op != Py_EQ && op != Py_NE) ||
        !PyObject_TypeCheck(a, &CMMatrixType) ||
        !PyObject_TypeCheck(b, &CMMatrixType))
        Py_RETURN_NOTIMPLEMENTED;
    const cm_matrix_t *x = &((CMMatrix *)a)->m, *y = &((CMMatrix *)b)->m;
    int eq = (x->xx==y->xx && x->yx==y->yx && x->xy==y->xy &&
              x->yy==y->yy && x->x0==y->x0 && x->y0==y->y0);
    if (op == Py_NE) eq = !eq;
    if (eq) Py_RETURN_TRUE;
    Py_RETURN_FALSE;
}

static PyMethodDef CMMatrix_methods[] = {
    {"init_rotate", (PyCFunction)CMMatrix_init_rotate, METH_VARARGS | METH_CLASS,
     "Matrix.init_rotate(radians) -> Matrix"},
    {"translate", (PyCFunction)CMMatrix_translate, METH_VARARGS, "translate(tx, ty) (in place)"},
    {"scale",     (PyCFunction)CMMatrix_scale,     METH_VARARGS, "scale(sx, sy) (in place)"},
    {"rotate",    (PyCFunction)CMMatrix_rotate,    METH_VARARGS, "rotate(radians) (in place)"},
    {"invert",    (PyCFunction)CMMatrix_invert,    METH_NOARGS,  "invert() (in place)"},
    {"multiply",  (PyCFunction)CMMatrix_multiply,  METH_O,       "multiply(other) -> Matrix"},
    {"transform_point",    (PyCFunction)CMMatrix_transform_point,    METH_VARARGS, "transform_point(x, y) -> (x, y)"},
    {"transform_distance", (PyCFunction)CMMatrix_transform_distance, METH_VARARGS, "transform_distance(dx, dy) -> (dx, dy)"},
    {"as_tuple",  (PyCFunction)CMMatrix_as_tuple,  METH_NOARGS,  "as_tuple() -> (xx,yx,xy,yy,x0,y0)"},
    {NULL}
};

/* Read/write the 6 components by name, like pycairo (m.xx, m.yx, ...). */
static PyMemberDef CMMatrix_members[] = {
    {"xx", T_DOUBLE, offsetof(CMMatrix, m.xx), 0, "xx component"},
    {"yx", T_DOUBLE, offsetof(CMMatrix, m.yx), 0, "yx component"},
    {"xy", T_DOUBLE, offsetof(CMMatrix, m.xy), 0, "xy component"},
    {"yy", T_DOUBLE, offsetof(CMMatrix, m.yy), 0, "yy component"},
    {"x0", T_DOUBLE, offsetof(CMMatrix, m.x0), 0, "x0 component"},
    {"y0", T_DOUBLE, offsetof(CMMatrix, m.y0), 0, "y0 component"},
    {NULL}
};

static PyNumberMethods CMMatrix_as_number = {
    .nb_multiply = CMMatrix_mul,
};

static PyTypeObject CMMatrixType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "cairo_metal.Matrix",
    .tp_basicsize = sizeof(CMMatrix),
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_doc = "Affine matrix (cm_matrix_t); fields xx,yx,xy,yy,x0,y0.",
    .tp_new = PyType_GenericNew,
    .tp_init = (initproc)CMMatrix_init,
    .tp_repr = (reprfunc)CMMatrix_repr,
    .tp_methods = CMMatrix_methods,
    .tp_members = CMMatrix_members,
    .tp_as_sequence = &CMMatrix_as_sequence,
    .tp_as_number = &CMMatrix_as_number,
    .tp_richcompare = CMMatrix_richcompare,
};

/* Helpers used everywhere a Matrix flows in/out of the C API. */
static PyObject *
matrix_from_cm(const cm_matrix_t *m)
{
    CMMatrix *o = PyObject_New(CMMatrix, &CMMatrixType);
    if (!o) return NULL;
    o->m = *m;
    return (PyObject *)o;
}
/* Accept a Matrix or a 6-sequence (xx,yx,xy,yy,x0,y0). */
static int
matrix_as_cm(PyObject *obj, cm_matrix_t *out)
{
    if (PyObject_TypeCheck(obj, &CMMatrixType)) {
        *out = ((CMMatrix *)obj)->m;
        return 0;
    }
    if (PySequence_Check(obj) && PySequence_Size(obj) == 6) {
        double v[6];
        for (int i = 0; i < 6; ++i) {
            PyObject *it = PySequence_GetItem(obj, i);
            if (!it) return -1;
            v[i] = PyFloat_AsDouble(it);
            Py_DECREF(it);
            if (PyErr_Occurred()) return -1;
        }
        out->xx=v[0]; out->yx=v[1]; out->xy=v[2]; out->yy=v[3]; out->x0=v[4]; out->y0=v[5];
        return 0;
    }
    PyErr_SetString(PyExc_TypeError, "expected a Matrix or a 6-sequence");
    return -1;
}

/* ===========================================================================
 * Surface (base) + ImageSurface + RecordingSurface
 * ---------------------------------------------------------------------------
 * One C struct backs all surface kinds; the Python type controls which
 * constructors apply.  `owns` is whether we must cm_surface_destroy on dealloc
 * (false for borrowed surfaces, e.g. cm_pattern_get_surface results).
 * =========================================================================== */
typedef struct {
    PyObject_HEAD
    cm_surface_t *surf;
    int           owns;
    PyObject     *databuf;   /* external buffer object (create_for_data) or NULL */
    Py_buffer     view;      /* writable view into databuf                       */
    int           has_view;
    int           width, height;
    PyObject     *map_parent;/* keepalive: the Surface a map-alias/subsurface needs */
    int           is_map_alias; /* 1 => map_parent is a map_to_image alias parent  */
} CMSurface;

/* Registry of live external-buffer (create_for_data) surfaces, so the manim
 * render hook can flush them all right before the frame's pixel_array is read
 * (manim never calls surface.flush() itself). */
#define CM_REG_MAX 64
static CMSurface *g_reg[CM_REG_MAX];
static int g_reg_n = 0;
static void cm_reg_add(CMSurface *s) { if (g_reg_n < CM_REG_MAX) g_reg[g_reg_n++] = s; }
static void cm_reg_del(CMSurface *s) {
    for (int i = 0; i < g_reg_n; ++i)
        if (g_reg[i] == s) { g_reg[i] = g_reg[--g_reg_n]; return; }
}
static long g_flush_total = 0, g_flush_nonempty = 0;

/* Commit pending GPU drawing and, if backed by an external buffer, copy the
 * rendered premultiplied-BGRA pixels back into it (manim's pixel_array). */
static void
cmsurface_sync(CMSurface *self)
{
    if (!self->surf) return;
    cm_surface_flush(self->surf);
    if (!self->has_view) return;

    size_t src_stride = 0;
    const unsigned char *src = (const unsigned char *)
        cm_surface_map_argb32(self->surf, &src_stride);
    if (!src || src_stride == 0) return;

    unsigned char *dst = (unsigned char *)self->view.buf;
    size_t dst_stride = (size_t)self->width * 4u;
    size_t row_bytes  = (size_t)self->width * 4u;
    Py_ssize_t cap    = self->view.len;
    int any_src = 0;
    for (int y = 0; y < self->height; ++y) {
        size_t doff = (size_t)y * dst_stride;
        if ((Py_ssize_t)(doff + row_bytes) > cap) break;
        const unsigned char *srow = src + (size_t)y * src_stride;
        unsigned char *drow = dst + doff;
        for (size_t x = 0; x < (size_t)self->width; ++x) {
            unsigned int sa = srow[x*4+3];
            if (sa) any_src = 1;
            if (sa == 255) {
                drow[x*4+0] = srow[x*4+0]; drow[x*4+1] = srow[x*4+1];
                drow[x*4+2] = srow[x*4+2]; drow[x*4+3] = 255;
            } else if (sa != 0) {
                unsigned int ia = 255u - sa;
                for (int ch = 0; ch < 4; ++ch) {
                    unsigned int v = srow[x*4+ch] + (drow[x*4+ch]*ia + 127u)/255u;
                    drow[x*4+ch] = (unsigned char)(v > 255u ? 255u : v);
                }
            }
        }
    }
    g_flush_total++;
    if (any_src) g_flush_nonempty++;
}

static void
CMSurface_dealloc(CMSurface *self)
{
    cm_reg_del(self);
    if (self->has_view) { PyBuffer_Release(&self->view); self->has_view = 0; }
    Py_XDECREF(self->databuf);
    /* A still-mapped image alias (user forgot unmap_image): tear the alias down
     * against its parent so we never leak it -- cm_surface_unmap_image frees the
     * lightweight wrapper without touching the parent's pixels (see cm_surface.m).
     * If the user already called unmap_image, surf is NULL and this is skipped.
     * A non-alias keepalive (a subsurface's parent) is NOT unmapped: the
     * subsurface is a real owned surface freed by the normal `owns` path below. */
    if (self->is_map_alias && self->map_parent) {
        CMSurface *p = (CMSurface *)self->map_parent;
        if (self->surf && p->surf) cm_surface_unmap_image(p->surf, self->surf);
        self->surf = NULL;           /* alias is owned by the map, not us */
    }
    if (self->surf && self->owns) cm_surface_destroy(self->surf);
    self->surf = NULL;
    /* Drop the keepalive (subsurface parent or alias parent) AFTER the C surface
     * is gone, so the parent's backing outlived the dependent surface. */
    Py_CLEAR(self->map_parent);
    Py_TYPE(self)->tp_free((PyObject *)self);
}

/* Wrap an existing cm_surface_t in the Python type matching its cm surface type
 * (so e.g. a returned image surface exposes ImageSurface.get_width()).  Used by
 * accessors that hand back borrowed/owned surfaces. */
static PyObject *
wrap_surface(cm_surface_t *surf, int owns)
{
    if (!surf) {
        if (cm_raise_if_error(cm_last_status()) < 0) return NULL;
        PyErr_SetString(CairoError, "cairo_metal: NULL surface");
        return NULL;
    }
    PyTypeObject *t;
    switch (cm_surface_get_type(surf)) {
        case CM_SURFACE_TYPE_RECORDING: t = &CMRecordingSurfaceType; break;
        case CM_SURFACE_TYPE_IMAGE:     t = &CMImageSurfaceType;     break;
        default:                        t = &CMImageSurfaceType;     break;
    }
    CMSurface *o = (CMSurface *)t->tp_alloc(t, 0);
    if (!o) { if (owns) cm_surface_destroy(surf); return NULL; }
    o->surf = surf; o->owns = owns;
    o->databuf = NULL; o->has_view = 0; o->map_parent = NULL;
    o->width = cm_surface_get_width(surf);
    o->height = cm_surface_get_height(surf);
    return (PyObject *)o;
}

/* ImageSurface(format, width, height) -- owns its pixels (pycairo style). */
static int
CMImageSurface_init(CMSurface *self, PyObject *args, PyObject *kwds)
{
    int fmt, w, h;
    if (!PyArg_ParseTuple(args, "iii", &fmt, &w, &h)) return -1;
    if (w <= 0 || h <= 0) {
        PyErr_SetString(PyExc_ValueError, "cairo_metal: width/height must be > 0");
        return -1;
    }
    self->surf = cm_image_surface_create((cm_format_t)fmt, w, h);
    if (!self->surf) {
        cm_raise_if_error(cm_last_status());
        if (!PyErr_Occurred())
            PyErr_SetString(CairoError, "cairo_metal: cm_image_surface_create failed");
        return -1;
    }
    self->owns = 1;
    self->width = cm_surface_get_width(self->surf);
    self->height = cm_surface_get_height(self->surf);
    self->databuf = NULL; self->has_view = 0; self->map_parent = NULL;
    return 0;
}

/* classmethod create_for_data(data, format, width, height[, stride]) */
static PyObject *
CMImageSurface_create_for_data(PyObject *cls, PyObject *args)
{
    PyObject *data;
    int fmt, w, h;
    long stride = 0; /* accepted for pycairo compat; we use w*4 ARGB32 contiguous */
    if (!PyArg_ParseTuple(args, "Oiii|l", &data, &fmt, &w, &h, &stride))
        return NULL;
    if (fmt != CM_FORMAT_ARGB32) {
        PyErr_SetString(PyExc_ValueError,
            "cairo_metal: create_for_data currently supports FORMAT_ARGB32 only");
        return NULL;
    }
    if (w <= 0 || h <= 0) {
        PyErr_SetString(PyExc_ValueError, "cairo_metal: width/height must be > 0");
        return NULL;
    }
    CMSurface *self = (CMSurface *)CMImageSurfaceType.tp_alloc(&CMImageSurfaceType, 0);
    if (!self) return NULL;
    self->surf = NULL; self->owns = 1; self->databuf = NULL; self->has_view = 0;
    self->map_parent = NULL;
    self->width = w; self->height = h;

    if (PyObject_GetBuffer(data, &self->view, PyBUF_WRITABLE | PyBUF_SIMPLE) != 0) {
        Py_DECREF(self); return NULL;
    }
    self->has_view = 1;
    if (self->view.len < (Py_ssize_t)w * h * 4) {
        PyErr_Format(PyExc_ValueError, "cairo_metal: data buffer too small (%zd < %d)",
                     (Py_ssize_t)self->view.len, w * h * 4);
        Py_DECREF(self); return NULL;
    }
    Py_INCREF(data); self->databuf = data;

    self->surf = cm_image_surface_create_argb32(CM_FORMAT_ARGB32, w, h);
    if (!self->surf) {
        cm_raise_if_error(cm_last_status());
        if (!PyErr_Occurred())
            PyErr_SetString(CairoError, "cairo_metal: cm_image_surface_create_argb32 failed");
        Py_DECREF(self); return NULL;
    }
    cm_reg_add(self);
    return (PyObject *)self;
}

/* classmethod create_from_png(path) -> ImageSurface */
static PyObject *
CMImageSurface_create_from_png(PyObject *cls, PyObject *args)
{
    const char *path;
    if (!PyArg_ParseTuple(args, "s", &path)) return NULL;
    cm_surface_t *s = cm_image_surface_create_from_png_path(path);
    if (!s) {
        if (cm_raise_if_error(cm_last_status()) < 0) return NULL;
        PyErr_Format(CairoError, "cairo_metal: could not read PNG '%s'", path);
        return NULL;
    }
    CMSurface *o = (CMSurface *)CMImageSurfaceType.tp_alloc(&CMImageSurfaceType, 0);
    if (!o) { cm_surface_destroy(s); return NULL; }
    o->surf = s; o->owns = 1; o->databuf = NULL; o->has_view = 0; o->map_parent = NULL;
    o->width = cm_surface_get_width(s); o->height = cm_surface_get_height(s);
    return (PyObject *)o;
}

/* format_stride_for_width(format, width) -- pycairo ImageSurface staticmethod. */
static PyObject *
CMImageSurface_format_stride_for_width(PyObject *cls, PyObject *args)
{
    int fmt, w;
    if (!PyArg_ParseTuple(args, "ii", &fmt, &w)) return NULL;
    return PyLong_FromLong(cm_format_stride_for_width((cm_format_t)fmt, w));
}

/* ---- shared Surface methods (base) ---- */
#define SURF_OR_NULL(self) \
    do { if (!((CMSurface*)(self))->surf) { \
        PyErr_SetString(CairoError, "cairo_metal: dead surface"); return NULL; } } while (0)

static PyObject *CMSurface_flush(CMSurface *self, PyObject *Py_UNUSED(i)) {
    SURF_OR_NULL(self); cmsurface_sync(self); Py_RETURN_NONE; }
static PyObject *CMSurface_finish(CMSurface *self, PyObject *Py_UNUSED(i)) {
    SURF_OR_NULL(self); cmsurface_sync(self); cm_surface_finish(self->surf); Py_RETURN_NONE; }
static PyObject *CMSurface_mark_dirty(CMSurface *self, PyObject *args) {
    SURF_OR_NULL(self);
    if (PyTuple_GET_SIZE(args) == 0) { cm_surface_mark_dirty(self->surf); Py_RETURN_NONE; }
    int x, y, w, h;
    if (!PyArg_ParseTuple(args, "iiii", &x, &y, &w, &h)) return NULL;
    cm_surface_mark_dirty_rectangle(self->surf, x, y, w, h);
    Py_RETURN_NONE; }
static PyObject *CMSurface_set_device_offset(CMSurface *self, PyObject *args) {
    SURF_OR_NULL(self); double x, y;
    if (!PyArg_ParseTuple(args, "dd", &x, &y)) return NULL;
    cm_surface_set_device_offset(self->surf, x, y); Py_RETURN_NONE; }
static PyObject *CMSurface_get_device_offset(CMSurface *self, PyObject *Py_UNUSED(i)) {
    SURF_OR_NULL(self); double x = 0, y = 0;
    cm_surface_get_device_offset(self->surf, &x, &y); return Py_BuildValue("(dd)", x, y); }
static PyObject *CMSurface_get_content(CMSurface *self, PyObject *Py_UNUSED(i)) {
    SURF_OR_NULL(self); return PyLong_FromLong((long)cm_surface_get_content(self->surf)); }
static PyObject *CMSurface_get_type(CMSurface *self, PyObject *Py_UNUSED(i)) {
    SURF_OR_NULL(self); return PyLong_FromLong((long)cm_surface_get_type(self->surf)); }
static PyObject *CMSurface_status(CMSurface *self, PyObject *Py_UNUSED(i)) {
    if (!self->surf) return PyLong_FromLong(0);
    return PyLong_FromLong(cm_to_cairo_status(cm_surface_status(self->surf))); }
static PyObject *CMSurface_get_iosurface(CMSurface *self, PyObject *Py_UNUSED(i)) {
    SURF_OR_NULL(self); cm_surface_flush(self->surf);
    void *io = cm_surface_get_iosurface(self->surf);
    return PyLong_FromVoidPtr(io); }
static PyObject *CMSurface_write_to_png(CMSurface *self, PyObject *args) {
    SURF_OR_NULL(self); const char *path;
    if (!PyArg_ParseTuple(args, "s", &path)) return NULL;
    cm_surface_flush(self->surf);
    if (cm_raise_if_error(cm_surface_write_to_png_path(self->surf, path)) < 0) return NULL;
    Py_RETURN_NONE; }

/* create_similar(content, width, height) -> Surface device-compatible with self.
 * Backed by cm_surface_create_similar (CONTENT -> concrete format). */
static PyObject *CMSurface_create_similar(CMSurface *self, PyObject *args) {
    SURF_OR_NULL(self); int content, w, h;
    if (!PyArg_ParseTuple(args, "iii", &content, &w, &h)) return NULL;
    cm_surface_t *s = cm_surface_create_similar(self->surf, (cm_content_t)content, w, h);
    return wrap_surface(s, 1);  /* owns: a fresh surface */ }

/* create_for_rectangle(x, y, width, height) -> Surface (subsurface view).
 * Backed by cm_surface_create_for_rectangle.  NOTE the new surface BORROWS the
 * parent's GPU backing, so we keep the parent Python object alive via map_parent
 * (reused as a generic keepalive here) so the parent outlives the subsurface. */
static PyObject *CMSurface_create_for_rectangle(CMSurface *self, PyObject *args) {
    SURF_OR_NULL(self); double x, y, w, h;
    if (!PyArg_ParseTuple(args, "dddd", &x, &y, &w, &h)) return NULL;
    cm_surface_t *sub = cm_surface_create_for_rectangle(self->surf, x, y, w, h);
    PyObject *o = wrap_surface(sub, 1);
    if (o) { Py_INCREF((PyObject *)self); ((CMSurface *)o)->map_parent = (PyObject *)self; }
    return o; }

/* map_to_image(extents=None) -> ImageSurface aliasing self's pixels.
 * Backed by cm_surface_map_to_image.  The returned image is owned by the MAP
 * (not a normal surface): it must be released with unmap_image(image) -- we set
 * owns=0 and remember the parent so dealloc can unmap if the user forgets. */
static PyObject *CMSurface_map_to_image(CMSurface *self, PyObject *args) {
    SURF_OR_NULL(self);
    PyObject *ext = Py_None;
    if (!PyArg_ParseTuple(args, "|O", &ext)) return NULL;
    cm_rectangle_int_t r, *rp = NULL;
    if (ext != Py_None) {
        if (!PyArg_ParseTuple(ext, "iiii", &r.x, &r.y, &r.width, &r.height)) {
            PyErr_SetString(PyExc_TypeError,
                "map_to_image extents must be None or (x, y, width, height)");
            return NULL;
        }
        rp = &r;
    }
    cm_surface_flush(self->surf);
    cm_surface_t *img = cm_surface_map_to_image(self->surf, rp);
    if (!img) {
        if (cm_raise_if_error(cm_last_status()) < 0) return NULL;
        PyErr_SetString(CairoError, "cairo_metal: map_to_image failed");
        return NULL;
    }
    /* Wrap as a non-owning ImageSurface; record the parent so unmap (or dealloc)
     * tears the alias down against it. */
    CMSurface *o = (CMSurface *)CMImageSurfaceType.tp_alloc(&CMImageSurfaceType, 0);
    if (!o) { cm_surface_unmap_image(self->surf, img); return NULL; }
    o->surf = img; o->owns = 0; o->databuf = NULL; o->has_view = 0;
    o->width = cm_surface_get_width(img); o->height = cm_surface_get_height(img);
    Py_INCREF((PyObject *)self); o->map_parent = (PyObject *)self;
    o->is_map_alias = 1;   /* dealloc unmaps against the parent if not done */
    return (PyObject *)o; }

/* unmap_image(image): write back + release a map_to_image alias.  Backed by
 * cm_surface_unmap_image.  After this the image surface is dead (its C surface is
 * detached so its dealloc does not double-free). */
static PyObject *CMSurface_unmap_image(CMSurface *self, PyObject *args) {
    SURF_OR_NULL(self);
    PyObject *imgo;
    if (!PyArg_ParseTuple(args, "O!", &CMSurfaceType, &imgo)) return NULL;
    CMSurface *img = (CMSurface *)imgo;
    if (!img->is_map_alias || img->map_parent != (PyObject *)self) {
        PyErr_SetString(CairoError,
            "cairo_metal: unmap_image image was not mapped from this surface");
        return NULL;
    }
    if (img->surf) {
        cm_surface_unmap_image(self->surf, img->surf);
        img->surf = NULL;   /* alias consumed by unmap */
    }
    img->is_map_alias = 0;
    Py_CLEAR(img->map_parent);
    Py_RETURN_NONE; }

/* ---- ImageSurface-specific methods ---- */
static PyObject *CMSurface_get_width(CMSurface *self, PyObject *Py_UNUSED(i)) {
    return PyLong_FromLong(self->width); }
static PyObject *CMSurface_get_height(CMSurface *self, PyObject *Py_UNUSED(i)) {
    return PyLong_FromLong(self->height); }
static PyObject *CMSurface_get_format(CMSurface *self, PyObject *Py_UNUSED(i)) {
    SURF_OR_NULL(self); return PyLong_FromLong((long)cm_surface_get_format(self->surf)); }
static PyObject *CMSurface_get_stride(CMSurface *self, PyObject *Py_UNUSED(i)) {
    SURF_OR_NULL(self);
    /* pycairo: get_stride() == ImageSurface.format_stride_for_width(format,width)
     * AND len(get_data()) == get_stride()*height, so data[y*get_stride()+x*bpp]
     * is in-bounds.  Report cairo's tightly-packed, 4-byte-aligned row stride
     * (the one get_data() below packs to), NOT the backing IOSurface's padded
     * hardware bytesPerRow -- that padding stays an internal detail of
     * cm_surface_map()/cm_surface_get_stride() and must not leak through here. */
    int s = cm_format_stride_for_width(cm_surface_get_format(self->surf), self->width);
    if (s <= 0) {   /* defensive: fall back to the contiguous width*bpp row */
        int bpp = cm_format_bytes_per_pixel(cm_surface_get_format(self->surf));
        if (bpp <= 0) bpp = 4;
        s = self->width * bpp;
    }
    return PyLong_FromLong(s); }

/* get_data() -> bytes (premultiplied native pixels, contiguous width*bpp). */
static PyObject *CMSurface_get_data(CMSurface *self, PyObject *Py_UNUSED(i)) {
    SURF_OR_NULL(self);
    cm_surface_flush(self->surf);
    size_t stride = 0;
    const char *src = (const char *)cm_surface_map(self->surf, &stride);
    if (!src || stride == 0) {
        if (cm_raise_if_error(cm_last_status()) < 0) return NULL;
        PyErr_SetString(CairoError, "cairo_metal: surface map failed");
        return NULL;
    }
    /* Pack to the CAIRO buffer stride == get_stride() ==
     * cm_format_stride_for_width(format,width), NOT the padded IOSurface
     * bytes-per-row: for widths whose packed row is not already 4-byte aligned
     * (e.g. A8 width 7 -> stride 8) the cairo stride differs from width*bpp, and
     * the pycairo contract is len(get_data()) == get_stride()*height with rows
     * exactly get_stride() bytes apart.  `src` rows are `stride` (the IOSurface
     * GPU bytes-per-row) apart, and stride >= cairo_row >= width*bpp, so copying
     * width*bpp meaningful bytes per row stays in bounds. */
    int bpp = cm_format_bytes_per_pixel(cm_surface_get_format(self->surf));
    if (bpp <= 0) bpp = 4;
    Py_ssize_t cairo_row = (Py_ssize_t)cm_format_stride_for_width(
                               cm_surface_get_format(self->surf), self->width);
    if (cairo_row < (Py_ssize_t)self->width * bpp)
        cairo_row = (Py_ssize_t)self->width * bpp;   /* defensive floor */
    Py_ssize_t copy_bytes = (Py_ssize_t)self->width * bpp;  /* meaningful px/row */
    PyObject *out = PyBytes_FromStringAndSize(NULL, cairo_row * self->height);
    if (!out) return NULL;
    char *dst = PyBytes_AS_STRING(out);
    memset(dst, 0, (size_t)(cairo_row * self->height));     /* zero pad bytes */
    for (int y = 0; y < self->height; ++y)
        memcpy(dst + y * cairo_row, src + (size_t)y * stride, (size_t)copy_bytes);
    return out;
}

/* create_similar_image(format, width, height) -> ImageSurface device-compatible
 * with self.  Backed by cm_surface_create_similar_image (always an image
 * surface, caller-named format). */
static PyObject *CMSurface_create_similar_image(CMSurface *self, PyObject *args) {
    SURF_OR_NULL(self); int fmt, w, h;
    if (!PyArg_ParseTuple(args, "iii", &fmt, &w, &h)) return NULL;
    cm_surface_t *s = cm_surface_create_similar_image(self->surf, (cm_format_t)fmt, w, h);
    return wrap_surface(s, 1); }

/* ---- RecordingSurface(content, extents-or-None) ---- */
static int
CMRecordingSurface_init(CMSurface *self, PyObject *args, PyObject *kwds)
{
    int content;
    PyObject *ext = Py_None;
    if (!PyArg_ParseTuple(args, "i|O", &content, &ext)) return -1;
    cm_rect_t r, *rp = NULL;
    if (ext != Py_None) {
        if (!PyArg_ParseTuple(ext, "dddd", &r.x, &r.y, &r.width, &r.height)) {
            PyErr_SetString(PyExc_TypeError,
                "RecordingSurface extents must be None or (x, y, width, height)");
            return -1;
        }
        rp = &r;
    }
    self->surf = cm_recording_surface_create((cm_content_t)content, rp);
    if (!self->surf) {
        cm_raise_if_error(cm_last_status());
        if (!PyErr_Occurred())
            PyErr_SetString(CairoError, "cairo_metal: cm_recording_surface_create failed");
        return -1;
    }
    self->owns = 1; self->databuf = NULL; self->has_view = 0; self->map_parent = NULL;
    self->width = cm_surface_get_width(self->surf);
    self->height = cm_surface_get_height(self->surf);
    return 0;
}
static PyObject *CMRecordingSurface_ink_extents(CMSurface *self, PyObject *Py_UNUSED(i)) {
    SURF_OR_NULL(self); cm_rect_t r = {0,0,0,0};
    cm_recording_surface_ink_extents(self->surf, &r);
    return Py_BuildValue("(dddd)", r.x, r.y, r.width, r.height); }
static PyObject *CMRecordingSurface_get_extents(CMSurface *self, PyObject *Py_UNUSED(i)) {
    SURF_OR_NULL(self); cm_rect_t r = {0,0,0,0};
    int bounded = cm_recording_surface_get_extents(self->surf, &r);
    if (!bounded) Py_RETURN_NONE;
    return Py_BuildValue("(dddd)", r.x, r.y, r.width, r.height); }

/* ---- method tables ---- */
static PyMethodDef CMSurface_base_methods[] = {
    {"flush",             (PyCFunction)CMSurface_flush,             METH_NOARGS,  "commit pending GPU drawing"},
    {"finish",            (PyCFunction)CMSurface_finish,            METH_NOARGS,  "flush + release backing"},
    {"mark_dirty",        (PyCFunction)CMSurface_mark_dirty,        METH_VARARGS, "mark_dirty([x, y, w, h])"},
    {"set_device_offset", (PyCFunction)CMSurface_set_device_offset, METH_VARARGS, "set_device_offset(x, y)"},
    {"get_device_offset", (PyCFunction)CMSurface_get_device_offset, METH_NOARGS,  "get_device_offset() -> (x, y)"},
    {"get_content",       (PyCFunction)CMSurface_get_content,       METH_NOARGS,  "get_content() -> Content"},
    {"get_type",          (PyCFunction)CMSurface_get_type,          METH_NOARGS,  "get_type() -> SurfaceType"},
    {"status",            (PyCFunction)CMSurface_status,            METH_NOARGS,  "status() -> Status int"},
    {"get_iosurface",     (PyCFunction)CMSurface_get_iosurface,     METH_NOARGS,  "IOSurfaceRef as int (0 if none)"},
    {"write_to_png",      (PyCFunction)CMSurface_write_to_png,      METH_VARARGS, "write_to_png(path)"},
    {"create_similar",    (PyCFunction)CMSurface_create_similar,    METH_VARARGS, "create_similar(content, width, height) -> Surface"},
    {"create_for_rectangle",(PyCFunction)CMSurface_create_for_rectangle,METH_VARARGS,"create_for_rectangle(x, y, width, height) -> Surface (subsurface)"},
    {"map_to_image",      (PyCFunction)CMSurface_map_to_image,      METH_VARARGS, "map_to_image([(x, y, w, h)]) -> ImageSurface aliasing the pixels"},
    {"unmap_image",       (PyCFunction)CMSurface_unmap_image,       METH_VARARGS, "unmap_image(image) -- write back + release a map_to_image alias"},
    {NULL}
};
static PyMethodDef CMImageSurface_methods[] = {
    {"create_for_data",        (PyCFunction)CMImageSurface_create_for_data,        METH_VARARGS | METH_CLASS,
     "create_for_data(data, format, width, height[, stride]) -> ImageSurface"},
    {"create_from_png",        (PyCFunction)CMImageSurface_create_from_png,        METH_VARARGS | METH_CLASS,
     "create_from_png(path) -> ImageSurface"},
    {"format_stride_for_width",(PyCFunction)CMImageSurface_format_stride_for_width,METH_VARARGS | METH_STATIC,
     "format_stride_for_width(format, width) -> int"},
    {"get_width",  (PyCFunction)CMSurface_get_width,  METH_NOARGS, "width in px"},
    {"get_height", (PyCFunction)CMSurface_get_height, METH_NOARGS, "height in px"},
    {"get_format", (PyCFunction)CMSurface_get_format, METH_NOARGS, "get_format() -> Format"},
    {"get_stride", (PyCFunction)CMSurface_get_stride, METH_NOARGS, "row stride in bytes"},
    {"get_data",   (PyCFunction)CMSurface_get_data,   METH_NOARGS, "bytes of premultiplied native pixels"},
    {"create_similar_image",(PyCFunction)CMSurface_create_similar_image,METH_VARARGS,"create_similar_image(format, width, height) -> ImageSurface"},
    {NULL}
};
static PyMethodDef CMRecordingSurface_methods[] = {
    {"ink_extents", (PyCFunction)CMRecordingSurface_ink_extents, METH_NOARGS, "ink_extents() -> (x, y, w, h)"},
    {"get_extents", (PyCFunction)CMRecordingSurface_get_extents, METH_NOARGS, "get_extents() -> (x, y, w, h) or None"},
    {NULL}
};

static PyTypeObject CMSurfaceType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "cairo_metal.Surface",
    .tp_basicsize = sizeof(CMSurface),
    .tp_flags = Py_TPFLAGS_DEFAULT | Py_TPFLAGS_BASETYPE,
    .tp_doc = "Base surface (cm_surface_t). Abstract: cannot be instantiated.",
    .tp_new = cm_abstract_new,   /* abstract base: TypeError on direct construct */
    .tp_dealloc = (destructor)CMSurface_dealloc,
    .tp_methods = CMSurface_base_methods,
};
static PyTypeObject CMImageSurfaceType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "cairo_metal.ImageSurface",
    .tp_basicsize = sizeof(CMSurface),
    .tp_flags = Py_TPFLAGS_DEFAULT | Py_TPFLAGS_BASETYPE,
    .tp_doc = "GPU-backed image surface (cm_surface_t).",
    .tp_base = &CMSurfaceType,
    .tp_new = PyType_GenericNew,
    .tp_init = (initproc)CMImageSurface_init,
    .tp_methods = CMImageSurface_methods,
};
static PyTypeObject CMRecordingSurfaceType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "cairo_metal.RecordingSurface",
    .tp_basicsize = sizeof(CMSurface),
    .tp_flags = Py_TPFLAGS_DEFAULT | Py_TPFLAGS_BASETYPE,
    .tp_doc = "Recording surface (op-log; cm_surface_t).",
    .tp_base = &CMSurfaceType,
    .tp_new = PyType_GenericNew,
    .tp_init = (initproc)CMRecordingSurface_init,
    .tp_methods = CMRecordingSurface_methods,
};

/* ===========================================================================
 * Pattern hierarchy
 * ---------------------------------------------------------------------------
 * Base Pattern (cm_pattern_t) + SolidPattern, SurfacePattern, Gradient(base),
 * LinearGradient, RadialGradient, MeshPattern.  One C struct; the Python type
 * gates which constructor + extra methods apply.
 * =========================================================================== */
typedef struct {
    PyObject_HEAD
    cm_pattern_t *pat;
    int           owns;
    PyObject     *keepalive;  /* e.g. the Surface a SurfacePattern wraps, or NULL */
} CMPattern;

static void
CMPattern_dealloc(CMPattern *self)
{
    if (self->pat && self->owns) cm_pattern_destroy(self->pat);
    self->pat = NULL;
    Py_XDECREF(self->keepalive);
    Py_TYPE(self)->tp_free((PyObject *)self);
}

/* Wrap an existing cm_pattern_t in the Python type that matches its cm type. */
static PyObject *
wrap_pattern(cm_pattern_t *pat, int owns)
{
    if (!pat) {
        if (cm_raise_if_error(cm_last_status()) < 0) return NULL;
        PyErr_SetString(CairoError, "cairo_metal: NULL pattern");
        return NULL;
    }
    PyTypeObject *t;
    switch (cm_pattern_get_type(pat)) {
        case CM_PATTERN_TYPE_SOLID:   t = &CMSolidPatternType;   break;
        case CM_PATTERN_TYPE_SURFACE: t = &CMSurfacePatternType; break;
        case CM_PATTERN_TYPE_LINEAR:  t = &CMLinearGradientType; break;
        case CM_PATTERN_TYPE_RADIAL:  t = &CMRadialGradientType; break;
        case CM_PATTERN_TYPE_MESH:    t = &CMMeshPatternType;    break;
        case CM_PATTERN_TYPE_RASTER_SOURCE: t = &CMRasterSourcePatternType; break;
        default:                      t = &CMPatternType;        break;
    }
    CMPattern *o = (CMPattern *)t->tp_alloc(t, 0);
    if (!o) { if (owns) cm_pattern_destroy(pat); return NULL; }
    o->pat = pat; o->owns = owns; o->keepalive = NULL;
    return (PyObject *)o;
}

/* ---- base Pattern accessors (extend / filter / matrix / type / status) ---- */
static PyObject *CMPattern_set_extend(CMPattern *self, PyObject *args) {
    int e; if (!PyArg_ParseTuple(args, "i", &e)) return NULL;
    cm_pattern_set_extend(self->pat, (cm_extend_t)e); Py_RETURN_NONE; }
static PyObject *CMPattern_get_extend(CMPattern *self, PyObject *Py_UNUSED(i)) {
    return PyLong_FromLong((long)cm_pattern_get_extend(self->pat)); }
static PyObject *CMPattern_set_filter(CMPattern *self, PyObject *args) {
    int f; if (!PyArg_ParseTuple(args, "i", &f)) return NULL;
    cm_pattern_set_filter(self->pat, (cm_filter_t)f); Py_RETURN_NONE; }
static PyObject *CMPattern_get_filter(CMPattern *self, PyObject *Py_UNUSED(i)) {
    return PyLong_FromLong((long)cm_pattern_get_filter(self->pat)); }
static PyObject *CMPattern_set_matrix(CMPattern *self, PyObject *arg) {
    cm_matrix_t m; if (matrix_as_cm(arg, &m) < 0) return NULL;
    cm_pattern_set_matrix(self->pat, &m); Py_RETURN_NONE; }
static PyObject *CMPattern_get_matrix(CMPattern *self, PyObject *Py_UNUSED(i)) {
    cm_matrix_t m; cm_pattern_get_matrix(self->pat, &m); return matrix_from_cm(&m); }
static PyObject *CMPattern_get_type(CMPattern *self, PyObject *Py_UNUSED(i)) {
    return PyLong_FromLong((long)cm_pattern_get_type(self->pat)); }
static PyObject *CMPattern_status(CMPattern *self, PyObject *Py_UNUSED(i)) {
    return PyLong_FromLong(cm_to_cairo_status(cm_pattern_status(self->pat))); }

static PyMethodDef CMPattern_methods[] = {
    {"set_extend", (PyCFunction)CMPattern_set_extend, METH_VARARGS, "set_extend(Extend)"},
    {"get_extend", (PyCFunction)CMPattern_get_extend, METH_NOARGS,  "get_extend() -> Extend"},
    {"set_filter", (PyCFunction)CMPattern_set_filter, METH_VARARGS, "set_filter(Filter)"},
    {"get_filter", (PyCFunction)CMPattern_get_filter, METH_NOARGS,  "get_filter() -> Filter"},
    {"set_matrix", (PyCFunction)CMPattern_set_matrix, METH_O,       "set_matrix(Matrix)"},
    {"get_matrix", (PyCFunction)CMPattern_get_matrix, METH_NOARGS,  "get_matrix() -> Matrix"},
    {"get_type",   (PyCFunction)CMPattern_get_type,   METH_NOARGS,  "get_type() -> PatternType"},
    {"status",     (PyCFunction)CMPattern_status,     METH_NOARGS,  "status() -> Status int"},
    {NULL}
};

static PyTypeObject CMPatternType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "cairo_metal.Pattern",
    .tp_basicsize = sizeof(CMPattern),
    .tp_flags = Py_TPFLAGS_DEFAULT | Py_TPFLAGS_BASETYPE,
    .tp_doc = "Base paint source (cm_pattern_t). Abstract: cannot be instantiated.",
    .tp_new = cm_abstract_new,   /* abstract base: TypeError on direct construct */
    .tp_dealloc = (destructor)CMPattern_dealloc,
    .tp_methods = CMPattern_methods,
};

/* ---- SolidPattern(r, g, b, a=1.0) ---- */
static int
CMSolidPattern_init(CMPattern *self, PyObject *args, PyObject *kwds)
{
    double r, g, b, a = 1.0;
    if (!PyArg_ParseTuple(args, "ddd|d", &r, &g, &b, &a)) return -1;
    self->pat = cm_solid_pattern_create_rgba(r, g, b, a);
    if (!self->pat) { PyErr_SetString(CairoError, "cm_solid_pattern_create_rgba failed"); return -1; }
    self->owns = 1; self->keepalive = NULL;
    return 0;
}
static PyObject *CMSolidPattern_get_rgba(CMPattern *self, PyObject *Py_UNUSED(i)) {
    double r, g, b, a;
    if (cm_raise_if_error(cm_solid_pattern_get_rgba(self->pat, &r, &g, &b, &a)) < 0) return NULL;
    return Py_BuildValue("(dddd)", r, g, b, a); }
static PyMethodDef CMSolidPattern_methods[] = {
    {"get_rgba", (PyCFunction)CMSolidPattern_get_rgba, METH_NOARGS, "get_rgba() -> (r, g, b, a)"},
    {NULL}
};
static PyTypeObject CMSolidPatternType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "cairo_metal.SolidPattern",
    .tp_basicsize = sizeof(CMPattern),
    .tp_flags = Py_TPFLAGS_DEFAULT | Py_TPFLAGS_BASETYPE,
    .tp_doc = "Solid colour pattern.",
    .tp_base = &CMPatternType,
    .tp_new = PyType_GenericNew,
    .tp_init = (initproc)CMSolidPattern_init,
    .tp_methods = CMSolidPattern_methods,
};

/* ---- SurfacePattern(surface) ---- */
static int
CMSurfacePattern_init(CMPattern *self, PyObject *args, PyObject *kwds)
{
    PyObject *surf;
    if (!PyArg_ParseTuple(args, "O!", &CMSurfaceType, &surf)) return -1;
    CMSurface *s = (CMSurface *)surf;
    if (!s->surf) { PyErr_SetString(CairoError, "cairo_metal: dead surface"); return -1; }
    self->pat = cm_pattern_create_for_surface(s->surf);
    if (!self->pat) { PyErr_SetString(CairoError, "cm_pattern_create_for_surface failed"); return -1; }
    self->owns = 1;
    /* OWNERSHIP (cairo refcount model): cm_pattern_create_for_surface took its OWN
     * lifetime reference on the surface (cm_surface_reference), and the surface is
     * refcounted -- cm_surface_destroy frees it only on the LAST reference.  So the
     * Python surface wrapper KEEPS its own reference (owns stays 1, dropped in
     * CMSurface_dealloc) and the pattern holds an independent one: the surface
     * survives as long as EITHER is alive.  This is what makes reusing one surface
     * across several SurfacePatterns / mask_surface() safe -- a temporary pattern
     * being released no longer frees a still-user-owned surface (the BUG-5 crash).
     * We still keep the Python surface object alive via `keepalive` so get_surface()
     * (which hands back the same C surface as a borrowed wrapper) stays consistent
     * and the wrapper's metadata (width/height) outlives the pattern. */
    Py_INCREF(surf); self->keepalive = surf;
    return 0;
}
static PyObject *CMSurfacePattern_get_surface(CMPattern *self, PyObject *Py_UNUSED(i)) {
    cm_surface_t *s = NULL;
    if (cm_raise_if_error(cm_surface_pattern_get_surface(self->pat, &s)) < 0) return NULL;
    return wrap_surface(s, 0);  /* borrowed: owned by the pattern */
}
static PyMethodDef CMSurfacePattern_methods[] = {
    {"get_surface", (PyCFunction)CMSurfacePattern_get_surface, METH_NOARGS, "get_surface() -> Surface"},
    {NULL}
};
static PyTypeObject CMSurfacePatternType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "cairo_metal.SurfacePattern",
    .tp_basicsize = sizeof(CMPattern),
    .tp_flags = Py_TPFLAGS_DEFAULT | Py_TPFLAGS_BASETYPE,
    .tp_doc = "Pattern sourced from a surface.",
    .tp_base = &CMPatternType,
    .tp_new = PyType_GenericNew,
    .tp_init = (initproc)CMSurfacePattern_init,
    .tp_methods = CMSurfacePattern_methods,
};

/* ---- RasterSourcePattern(content, width, height) ----
 * cairo's cairo_pattern_create_raster_source(): a pattern whose pixels are
 * produced on demand.  The C engine (cm_raster.c) fully backs it -- including
 * acquire/release callbacks driving the GPU cover pass -- but those callbacks are
 * C function pointers with a surface-marshalling + target/extents signature; a
 * Python callback across that boundary (with the GIL + wrapping the transient
 * target surface back into a Python object on every paint) is not wired here.
 * What IS exposed and works end to end:
 *   - construction (records content + nominal size);
 *   - the inherited base-Pattern set/get_extend / filter / matrix;
 *   - get_callback_data() (the user_data recorded at create time, NULL here);
 * and, with no callback installed, the engine's documented FALLBACK: the pattern
 * degenerates to a plain SurfacePattern over a pre-captured blank surface of the
 * content's format at the nominal size, so set_source(raster) + paint() draws
 * that (transparent) source instead of failing.  The user_data is fixed at NULL
 * (no Python object is handed to an unwired C callback). */
static int CMRasterSourcePattern_init(CMPattern *self, PyObject *args, PyObject *kwds) {
    int content, w, h;
    if (!PyArg_ParseTuple(args, "iii", &content, &w, &h)) return -1;
    self->pat = cm_pattern_create_raster_source(NULL, (cm_content_t)content, w, h);
    if (!self->pat) {
        cm_raise_if_error(cm_last_status());
        if (!PyErr_Occurred())
            PyErr_SetString(CairoError, "cm_pattern_create_raster_source failed");
        return -1;
    }
    self->owns = 1; self->keepalive = NULL;
    return 0;
}
static PyObject *CMRasterSourcePattern_get_callback_data(CMPattern *self, PyObject *Py_UNUSED(i)) {
    return PyLong_FromVoidPtr(cm_raster_source_pattern_get_user_data(self->pat)); }
static PyMethodDef CMRasterSourcePattern_methods[] = {
    {"get_callback_data", (PyCFunction)CMRasterSourcePattern_get_callback_data, METH_NOARGS,
     "get_callback_data() -> int (the user_data pointer; 0/NULL here)"},
    {NULL}
};
static PyTypeObject CMRasterSourcePatternType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "cairo_metal.RasterSourcePattern",
    .tp_basicsize = sizeof(CMPattern),
    .tp_flags = Py_TPFLAGS_DEFAULT | Py_TPFLAGS_BASETYPE,
    .tp_doc = "On-demand raster source pattern (construct + extend/filter/matrix; "
              "Python acquire/release callbacks are not wired -- see source).",
    .tp_base = &CMPatternType,
    .tp_new = PyType_GenericNew,
    .tp_init = (initproc)CMRasterSourcePattern_init,
    .tp_methods = CMRasterSourcePattern_methods,
};

/* ---- Gradient (base; color-stop API shared by Linear/Radial) ---- */
static PyObject *CMGradient_add_color_stop_rgba(CMPattern *self, PyObject *args) {
    double off, r, g, b, a;
    if (!PyArg_ParseTuple(args, "ddddd", &off, &r, &g, &b, &a)) return NULL;
    cm_pattern_add_color_stop_rgba(self->pat, off, r, g, b, a); Py_RETURN_NONE; }
static PyObject *CMGradient_add_color_stop_rgb(CMPattern *self, PyObject *args) {
    double off, r, g, b;
    if (!PyArg_ParseTuple(args, "dddd", &off, &r, &g, &b)) return NULL;
    cm_pattern_add_color_stop_rgb(self->pat, off, r, g, b); Py_RETURN_NONE; }
static PyObject *CMGradient_get_color_stops_rgba(CMPattern *self, PyObject *Py_UNUSED(i)) {
    int n = 0;
    if (cm_raise_if_error(cm_pattern_get_color_stop_count(self->pat, &n)) < 0) return NULL;
    PyObject *list = PyList_New(n);
    if (!list) return NULL;
    for (int k = 0; k < n; ++k) {
        double off, r, g, b, a;
        if (cm_raise_if_error(cm_pattern_get_color_stop_rgba(self->pat, k, &off, &r, &g, &b, &a)) < 0) {
            Py_DECREF(list); return NULL;
        }
        PyObject *t = Py_BuildValue("(ddddd)", off, r, g, b, a);
        if (!t) { Py_DECREF(list); return NULL; }
        PyList_SET_ITEM(list, k, t);
    }
    return list;
}
static PyObject *CMGradient_get_color_stop_count(CMPattern *self, PyObject *Py_UNUSED(i)) {
    int n = 0;
    if (cm_raise_if_error(cm_pattern_get_color_stop_count(self->pat, &n)) < 0) return NULL;
    return PyLong_FromLong(n);
}
static PyMethodDef CMGradient_methods[] = {
    {"add_color_stop_rgba", (PyCFunction)CMGradient_add_color_stop_rgba, METH_VARARGS, "add_color_stop_rgba(offset, r, g, b, a)"},
    {"add_color_stop_rgb",  (PyCFunction)CMGradient_add_color_stop_rgb,  METH_VARARGS, "add_color_stop_rgb(offset, r, g, b)"},
    {"get_color_stops_rgba",(PyCFunction)CMGradient_get_color_stops_rgba,METH_NOARGS,  "get_color_stops_rgba() -> [(off,r,g,b,a), ...]"},
    {"get_color_stop_count",(PyCFunction)CMGradient_get_color_stop_count,METH_NOARGS,  "get_color_stop_count() -> int"},
    {NULL}
};
static PyTypeObject CMGradientType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "cairo_metal.Gradient",
    .tp_basicsize = sizeof(CMPattern),
    .tp_flags = Py_TPFLAGS_DEFAULT | Py_TPFLAGS_BASETYPE,
    .tp_doc = "Base gradient pattern (color stops). Abstract: cannot be instantiated.",
    .tp_base = &CMPatternType,
    .tp_new = cm_abstract_new,   /* abstract base: TypeError on direct construct */
    .tp_methods = CMGradient_methods,
};

/* ---- LinearGradient(x0, y0, x1, y1) ---- */
static int
CMLinearGradient_init(CMPattern *self, PyObject *args, PyObject *kwds)
{
    double x0, y0, x1, y1;
    if (!PyArg_ParseTuple(args, "dddd", &x0, &y0, &x1, &y1)) return -1;
    self->pat = cm_linear_gradient_create(x0, y0, x1, y1);
    if (!self->pat) { PyErr_SetString(CairoError, "cm_linear_gradient_create failed"); return -1; }
    self->owns = 1; self->keepalive = NULL;
    return 0;
}
static PyObject *CMLinearGradient_get_linear_points(CMPattern *self, PyObject *Py_UNUSED(i)) {
    double x0, y0, x1, y1;
    if (cm_raise_if_error(cm_linear_gradient_get_points(self->pat, &x0, &y0, &x1, &y1)) < 0) return NULL;
    return Py_BuildValue("(dddd)", x0, y0, x1, y1); }
static PyMethodDef CMLinearGradient_methods[] = {
    {"get_linear_points", (PyCFunction)CMLinearGradient_get_linear_points, METH_NOARGS, "get_linear_points() -> (x0, y0, x1, y1)"},
    {NULL}
};
static PyTypeObject CMLinearGradientType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "cairo_metal.LinearGradient",
    .tp_basicsize = sizeof(CMPattern),
    .tp_flags = Py_TPFLAGS_DEFAULT | Py_TPFLAGS_BASETYPE,
    .tp_doc = "Linear gradient pattern.",
    .tp_base = &CMGradientType,
    .tp_new = PyType_GenericNew,
    .tp_init = (initproc)CMLinearGradient_init,
    .tp_methods = CMLinearGradient_methods,
};

/* ---- RadialGradient(cx0, cy0, r0, cx1, cy1, r1) ---- */
static int
CMRadialGradient_init(CMPattern *self, PyObject *args, PyObject *kwds)
{
    double cx0, cy0, r0, cx1, cy1, r1;
    if (!PyArg_ParseTuple(args, "dddddd", &cx0, &cy0, &r0, &cx1, &cy1, &r1)) return -1;
    self->pat = cm_radial_gradient_create(cx0, cy0, r0, cx1, cy1, r1);
    if (!self->pat) { PyErr_SetString(CairoError, "cm_radial_gradient_create failed"); return -1; }
    self->owns = 1; self->keepalive = NULL;
    return 0;
}
static PyObject *CMRadialGradient_get_radial_circles(CMPattern *self, PyObject *Py_UNUSED(i)) {
    double cx0, cy0, r0, cx1, cy1, r1;
    if (cm_raise_if_error(cm_radial_gradient_get_circles(self->pat, &cx0, &cy0, &r0, &cx1, &cy1, &r1)) < 0) return NULL;
    return Py_BuildValue("(dddddd)", cx0, cy0, r0, cx1, cy1, r1); }
static PyMethodDef CMRadialGradient_methods[] = {
    {"get_radial_circles", (PyCFunction)CMRadialGradient_get_radial_circles, METH_NOARGS, "get_radial_circles() -> (cx0, cy0, r0, cx1, cy1, r1)"},
    {NULL}
};
static PyTypeObject CMRadialGradientType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "cairo_metal.RadialGradient",
    .tp_basicsize = sizeof(CMPattern),
    .tp_flags = Py_TPFLAGS_DEFAULT | Py_TPFLAGS_BASETYPE,
    .tp_doc = "Radial gradient pattern.",
    .tp_base = &CMGradientType,
    .tp_new = PyType_GenericNew,
    .tp_init = (initproc)CMRadialGradient_init,
    .tp_methods = CMRadialGradient_methods,
};

/* ---- MeshPattern() (Coons patches) ---- */
static int
CMMeshPattern_init(CMPattern *self, PyObject *args, PyObject *kwds)
{
    if (!PyArg_ParseTuple(args, "")) return -1;
    self->pat = cm_mesh_pattern_create();
    if (!self->pat) { PyErr_SetString(CairoError, "cm_mesh_pattern_create failed"); return -1; }
    self->owns = 1; self->keepalive = NULL;
    return 0;
}
static PyObject *CMMesh_begin_patch(CMPattern *self, PyObject *Py_UNUSED(i)) {
    cm_mesh_pattern_begin_patch(self->pat); Py_RETURN_NONE; }
static PyObject *CMMesh_end_patch(CMPattern *self, PyObject *Py_UNUSED(i)) {
    cm_mesh_pattern_end_patch(self->pat); Py_RETURN_NONE; }
static PyObject *CMMesh_move_to(CMPattern *self, PyObject *args) {
    double x, y; if (!PyArg_ParseTuple(args, "dd", &x, &y)) return NULL;
    cm_mesh_pattern_move_to(self->pat, x, y); Py_RETURN_NONE; }
static PyObject *CMMesh_line_to(CMPattern *self, PyObject *args) {
    double x, y; if (!PyArg_ParseTuple(args, "dd", &x, &y)) return NULL;
    cm_mesh_pattern_line_to(self->pat, x, y); Py_RETURN_NONE; }
static PyObject *CMMesh_curve_to(CMPattern *self, PyObject *args) {
    double x1, y1, x2, y2, x3, y3;
    if (!PyArg_ParseTuple(args, "dddddd", &x1, &y1, &x2, &y2, &x3, &y3)) return NULL;
    cm_mesh_pattern_curve_to(self->pat, x1, y1, x2, y2, x3, y3); Py_RETURN_NONE; }
static PyObject *CMMesh_set_control_point(CMPattern *self, PyObject *args) {
    unsigned int pn; double x, y;
    if (!PyArg_ParseTuple(args, "Idd", &pn, &x, &y)) return NULL;
    cm_mesh_pattern_set_control_point(self->pat, pn, x, y); Py_RETURN_NONE; }
static PyObject *CMMesh_set_corner_color_rgb(CMPattern *self, PyObject *args) {
    unsigned int cn; double r, g, b;
    if (!PyArg_ParseTuple(args, "Iddd", &cn, &r, &g, &b)) return NULL;
    cm_mesh_pattern_set_corner_color_rgb(self->pat, cn, r, g, b); Py_RETURN_NONE; }
static PyObject *CMMesh_set_corner_color_rgba(CMPattern *self, PyObject *args) {
    unsigned int cn; double r, g, b, a;
    if (!PyArg_ParseTuple(args, "Idddd", &cn, &r, &g, &b, &a)) return NULL;
    cm_mesh_pattern_set_corner_color_rgba(self->pat, cn, r, g, b, a); Py_RETURN_NONE; }
static PyObject *CMMesh_get_patch_count(CMPattern *self, PyObject *Py_UNUSED(i)) {
    unsigned int c = 0;
    if (cm_raise_if_error(cm_mesh_pattern_get_patch_count(self->pat, &c)) < 0) return NULL;
    return PyLong_FromUnsignedLong(c); }
static PyObject *CMMesh_get_control_point(CMPattern *self, PyObject *args) {
    unsigned int patch, pn; double x, y;
    if (!PyArg_ParseTuple(args, "II", &patch, &pn)) return NULL;
    if (cm_raise_if_error(cm_mesh_pattern_get_control_point(self->pat, patch, pn, &x, &y)) < 0) return NULL;
    return Py_BuildValue("(dd)", x, y); }
static PyObject *CMMesh_get_corner_color_rgba(CMPattern *self, PyObject *args) {
    unsigned int patch, cn; double r, g, b, a;
    if (!PyArg_ParseTuple(args, "II", &patch, &cn)) return NULL;
    if (cm_raise_if_error(cm_mesh_pattern_get_corner_color_rgba(self->pat, patch, cn, &r, &g, &b, &a)) < 0) return NULL;
    return Py_BuildValue("(dddd)", r, g, b, a); }
static PyMethodDef CMMesh_methods[] = {
    {"begin_patch",            (PyCFunction)CMMesh_begin_patch,            METH_NOARGS,  "begin_patch()"},
    {"end_patch",              (PyCFunction)CMMesh_end_patch,              METH_NOARGS,  "end_patch()"},
    {"move_to",                (PyCFunction)CMMesh_move_to,                METH_VARARGS, "move_to(x, y)"},
    {"line_to",                (PyCFunction)CMMesh_line_to,                METH_VARARGS, "line_to(x, y)"},
    {"curve_to",               (PyCFunction)CMMesh_curve_to,               METH_VARARGS, "curve_to(x1, y1, x2, y2, x3, y3)"},
    {"set_control_point",      (PyCFunction)CMMesh_set_control_point,      METH_VARARGS, "set_control_point(n, x, y)"},
    {"set_corner_color_rgb",   (PyCFunction)CMMesh_set_corner_color_rgb,   METH_VARARGS, "set_corner_color_rgb(n, r, g, b)"},
    {"set_corner_color_rgba",  (PyCFunction)CMMesh_set_corner_color_rgba,  METH_VARARGS, "set_corner_color_rgba(n, r, g, b, a)"},
    {"get_patch_count",        (PyCFunction)CMMesh_get_patch_count,        METH_NOARGS,  "get_patch_count() -> int"},
    {"get_control_point",      (PyCFunction)CMMesh_get_control_point,      METH_VARARGS, "get_control_point(patch, n) -> (x, y)"},
    {"get_corner_color_rgba",  (PyCFunction)CMMesh_get_corner_color_rgba,  METH_VARARGS, "get_corner_color_rgba(patch, n) -> (r, g, b, a)"},
    {NULL}
};
static PyTypeObject CMMeshPatternType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "cairo_metal.MeshPattern",
    .tp_basicsize = sizeof(CMPattern),
    .tp_flags = Py_TPFLAGS_DEFAULT | Py_TPFLAGS_BASETYPE,
    .tp_doc = "Mesh (Coons-patch) pattern.",
    .tp_base = &CMPatternType,
    .tp_new = PyType_GenericNew,
    .tp_init = (initproc)CMMeshPattern_init,
    .tp_methods = CMMesh_methods,
};

/* ===========================================================================
 * Region  (cairo_region_t: integer rectangle-set algebra)
 * =========================================================================== */
typedef struct {
    PyObject_HEAD
    cm_region_t *region;
} CMRegion;

static void
CMRegion_dealloc(CMRegion *self)
{
    if (self->region) { cm_region_destroy(self->region); self->region = NULL; }
    Py_TYPE(self)->tp_free((PyObject *)self);
}

/* Pull a (x, y, w, h) tuple OR a RectangleInt-like 4-sequence into a cm rect. */
static int
rect_int_from_obj(PyObject *o, cm_rectangle_int_t *out)
{
    if (!PyArg_ParseTuple(o, "iiii", &out->x, &out->y, &out->width, &out->height)) {
        PyErr_Clear();
        if (PySequence_Check(o) && PySequence_Size(o) == 4) {
            long v[4];
            for (int i = 0; i < 4; ++i) {
                PyObject *it = PySequence_GetItem(o, i);
                if (!it) return -1;
                v[i] = PyLong_AsLong(it); Py_DECREF(it);
                if (PyErr_Occurred()) return -1;
            }
            out->x=(int)v[0]; out->y=(int)v[1]; out->width=(int)v[2]; out->height=(int)v[3];
            return 0;
        }
        PyErr_SetString(PyExc_TypeError, "expected (x, y, width, height)");
        return -1;
    }
    return 0;
}

/* Region() | Region((x,y,w,h)) | Region([(x,y,w,h), ...]) */
static int
CMRegion_init(CMRegion *self, PyObject *args, PyObject *kwds)
{
    PyObject *arg = NULL;
    if (!PyArg_ParseTuple(args, "|O", &arg)) return -1;
    if (arg == NULL || arg == Py_None) {
        self->region = cm_region_create();
    } else if (PyList_Check(arg)) {
        Py_ssize_t n = PyList_GET_SIZE(arg);
        cm_rectangle_int_t *rects = PyMem_Malloc(sizeof(cm_rectangle_int_t) * (n > 0 ? n : 1));
        if (!rects) { PyErr_NoMemory(); return -1; }
        for (Py_ssize_t i = 0; i < n; ++i) {
            if (rect_int_from_obj(PyList_GET_ITEM(arg, i), &rects[i]) < 0) { PyMem_Free(rects); return -1; }
        }
        self->region = cm_region_create_rectangles(rects, (int)n);
        PyMem_Free(rects);
    } else {
        cm_rectangle_int_t r;
        if (rect_int_from_obj(arg, &r) < 0) return -1;
        self->region = cm_region_create_rectangle(&r);
    }
    if (!self->region) { PyErr_SetString(CairoError, "cm_region_create failed"); return -1; }
    return 0;
}

static PyObject *wrap_region(cm_region_t *r) {
    if (!r) { PyErr_SetString(CairoError, "cairo_metal: NULL region"); return NULL; }
    CMRegion *o = (CMRegion *)CMRegionType.tp_alloc(&CMRegionType, 0);
    if (!o) { cm_region_destroy(r); return NULL; }
    o->region = r; return (PyObject *)o;
}

static PyObject *CMRegion_copy(CMRegion *self, PyObject *Py_UNUSED(i)) {
    return wrap_region(cm_region_copy(self->region)); }
static PyObject *CMRegion_status(CMRegion *self, PyObject *Py_UNUSED(i)) {
    return PyLong_FromLong(cm_to_cairo_status(cm_region_status(self->region))); }
static PyObject *CMRegion_is_empty(CMRegion *self, PyObject *Py_UNUSED(i)) {
    return PyBool_FromLong(cm_region_is_empty(self->region)); }
static PyObject *CMRegion_num_rectangles(CMRegion *self, PyObject *Py_UNUSED(i)) {
    return PyLong_FromLong(cm_region_num_rectangles(self->region)); }
static PyObject *CMRegion_get_extents(CMRegion *self, PyObject *Py_UNUSED(i)) {
    cm_rectangle_int_t e = {0,0,0,0}; cm_region_get_extents(self->region, &e);
    return Py_BuildValue("(iiii)", e.x, e.y, e.width, e.height); }
static PyObject *CMRegion_get_rectangle(CMRegion *self, PyObject *args) {
    int nth; if (!PyArg_ParseTuple(args, "i", &nth)) return NULL;
    cm_rectangle_int_t r = {0,0,0,0}; cm_region_get_rectangle(self->region, nth, &r);
    return Py_BuildValue("(iiii)", r.x, r.y, r.width, r.height); }
static PyObject *CMRegion_contains_point(CMRegion *self, PyObject *args) {
    int x, y; if (!PyArg_ParseTuple(args, "ii", &x, &y)) return NULL;
    return PyBool_FromLong(cm_region_contains_point(self->region, x, y)); }
static PyObject *CMRegion_contains_rectangle(CMRegion *self, PyObject *arg) {
    cm_rectangle_int_t r;
    if (rect_int_from_obj(arg, &r) < 0) return NULL;
    return PyLong_FromLong((long)cm_region_contains_rectangle(self->region, &r)); }
static PyObject *CMRegion_translate(CMRegion *self, PyObject *args) {
    int dx, dy; if (!PyArg_ParseTuple(args, "ii", &dx, &dy)) return NULL;
    cm_region_translate(self->region, dx, dy); Py_RETURN_NONE; }

/* Set ops accept a Region or a rectangle 4-tuple, like pycairo. */
typedef cm_status_t (*region_op_t)(cm_region_t *, const cm_region_t *);
typedef cm_status_t (*region_oprect_t)(cm_region_t *, const cm_rectangle_int_t *);
static PyObject *region_binop(CMRegion *self, PyObject *arg, region_op_t op, region_oprect_t oprect) {
    if (PyObject_TypeCheck(arg, &CMRegionType)) {
        if (cm_raise_if_error(op(self->region, ((CMRegion *)arg)->region)) < 0) return NULL;
    } else {
        cm_rectangle_int_t r;
        if (rect_int_from_obj(arg, &r) < 0) return NULL;
        if (cm_raise_if_error(oprect(self->region, &r)) < 0) return NULL;
    }
    Py_RETURN_NONE;
}
static PyObject *CMRegion_union(CMRegion *self, PyObject *a) {
    return region_binop(self, a, cm_region_union, cm_region_union_rectangle); }
static PyObject *CMRegion_intersect(CMRegion *self, PyObject *a) {
    return region_binop(self, a, cm_region_intersect, cm_region_intersect_rectangle); }
static PyObject *CMRegion_subtract(CMRegion *self, PyObject *a) {
    return region_binop(self, a, cm_region_subtract, cm_region_subtract_rectangle); }
static PyObject *CMRegion_xor(CMRegion *self, PyObject *a) {
    return region_binop(self, a, cm_region_xor, cm_region_xor_rectangle); }

static PyObject *CMRegion_richcompare(PyObject *a, PyObject *b, int op) {
    if ((op != Py_EQ && op != Py_NE) ||
        !PyObject_TypeCheck(a, &CMRegionType) || !PyObject_TypeCheck(b, &CMRegionType))
        Py_RETURN_NOTIMPLEMENTED;
    int eq = cm_region_equal(((CMRegion *)a)->region, ((CMRegion *)b)->region);
    if (op == Py_NE) eq = !eq;
    return PyBool_FromLong(eq);
}

static PyMethodDef CMRegion_methods[] = {
    {"copy",                (PyCFunction)CMRegion_copy,                METH_NOARGS,  "copy() -> Region"},
    {"status",              (PyCFunction)CMRegion_status,              METH_NOARGS,  "status() -> Status int"},
    {"is_empty",            (PyCFunction)CMRegion_is_empty,            METH_NOARGS,  "is_empty() -> bool"},
    {"num_rectangles",      (PyCFunction)CMRegion_num_rectangles,      METH_NOARGS,  "num_rectangles() -> int"},
    {"get_extents",         (PyCFunction)CMRegion_get_extents,         METH_NOARGS,  "get_extents() -> (x, y, w, h)"},
    {"get_rectangle",       (PyCFunction)CMRegion_get_rectangle,       METH_VARARGS, "get_rectangle(nth) -> (x, y, w, h)"},
    {"contains_point",      (PyCFunction)CMRegion_contains_point,      METH_VARARGS, "contains_point(x, y) -> bool"},
    {"contains_rectangle",  (PyCFunction)CMRegion_contains_rectangle,  METH_O,       "contains_rectangle((x, y, w, h)) -> RegionOverlap"},
    {"translate",           (PyCFunction)CMRegion_translate,           METH_VARARGS, "translate(dx, dy)"},
    {"union",               (PyCFunction)CMRegion_union,               METH_O,       "union(Region|rect) (in place)"},
    {"intersect",           (PyCFunction)CMRegion_intersect,           METH_O,       "intersect(Region|rect) (in place)"},
    {"subtract",            (PyCFunction)CMRegion_subtract,            METH_O,       "subtract(Region|rect) (in place)"},
    {"xor_",                (PyCFunction)CMRegion_xor,                 METH_O,       "xor_(Region|rect) (in place)"},
    {NULL}
};
static PyTypeObject CMRegionType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "cairo_metal.Region",
    .tp_basicsize = sizeof(CMRegion),
    .tp_flags = Py_TPFLAGS_DEFAULT | Py_TPFLAGS_BASETYPE,
    .tp_doc = "Integer rectangle-set (cm_region_t).",
    .tp_new = PyType_GenericNew,
    .tp_init = (initproc)CMRegion_init,
    .tp_dealloc = (destructor)CMRegion_dealloc,
    .tp_methods = CMRegion_methods,
    .tp_richcompare = CMRegion_richcompare,
};

/* ===========================================================================
 * FontOptions  (cm_font_options_t)
 * =========================================================================== */
typedef struct {
    PyObject_HEAD
    cm_font_options_t *opt;
} CMFontOptions;

static void CMFontOptions_dealloc(CMFontOptions *self) {
    if (self->opt) { cm_font_options_destroy(self->opt); self->opt = NULL; }
    Py_TYPE(self)->tp_free((PyObject *)self); }
static int CMFontOptions_init(CMFontOptions *self, PyObject *args, PyObject *kwds) {
    if (!PyArg_ParseTuple(args, "")) return -1;
    self->opt = cm_font_options_create();
    if (!self->opt) { PyErr_SetString(CairoError, "cm_font_options_create failed"); return -1; }
    return 0; }
static PyObject *wrap_font_options(cm_font_options_t *o) {
    if (!o) { PyErr_SetString(CairoError, "cairo_metal: NULL font options"); return NULL; }
    CMFontOptions *r = (CMFontOptions *)CMFontOptionsType.tp_alloc(&CMFontOptionsType, 0);
    if (!r) { cm_font_options_destroy(o); return NULL; }
    r->opt = o; return (PyObject *)r; }

static PyObject *CMFontOptions_copy(CMFontOptions *self, PyObject *Py_UNUSED(i)) {
    return wrap_font_options(cm_font_options_copy(self->opt)); }
static PyObject *CMFontOptions_merge(CMFontOptions *self, PyObject *arg) {
    if (!PyObject_TypeCheck(arg, &CMFontOptionsType)) {
        PyErr_SetString(PyExc_TypeError, "merge expects FontOptions"); return NULL; }
    cm_font_options_merge(self->opt, ((CMFontOptions *)arg)->opt); Py_RETURN_NONE; }
static PyObject *CMFontOptions_hash(CMFontOptions *self, PyObject *Py_UNUSED(i)) {
    return PyLong_FromUnsignedLong(cm_font_options_hash(self->opt)); }
static PyObject *CMFontOptions_status(CMFontOptions *self, PyObject *Py_UNUSED(i)) {
    return PyLong_FromLong(cm_to_cairo_status(cm_font_options_status(self->opt))); }
static PyObject *CMFontOptions_set_antialias(CMFontOptions *self, PyObject *args) {
    int v; if (!PyArg_ParseTuple(args, "i", &v)) return NULL;
    cm_font_options_set_antialias(self->opt, (cm_antialias_t)v); Py_RETURN_NONE; }
static PyObject *CMFontOptions_get_antialias(CMFontOptions *self, PyObject *Py_UNUSED(i)) {
    return PyLong_FromLong((long)cm_font_options_get_antialias(self->opt)); }
static PyObject *CMFontOptions_set_subpixel_order(CMFontOptions *self, PyObject *args) {
    int v; if (!PyArg_ParseTuple(args, "i", &v)) return NULL;
    cm_font_options_set_subpixel_order(self->opt, (cm_subpixel_order_t)v); Py_RETURN_NONE; }
static PyObject *CMFontOptions_get_subpixel_order(CMFontOptions *self, PyObject *Py_UNUSED(i)) {
    return PyLong_FromLong((long)cm_font_options_get_subpixel_order(self->opt)); }
static PyObject *CMFontOptions_set_hint_style(CMFontOptions *self, PyObject *args) {
    int v; if (!PyArg_ParseTuple(args, "i", &v)) return NULL;
    cm_font_options_set_hint_style(self->opt, (cm_hint_style_t)v); Py_RETURN_NONE; }
static PyObject *CMFontOptions_get_hint_style(CMFontOptions *self, PyObject *Py_UNUSED(i)) {
    return PyLong_FromLong((long)cm_font_options_get_hint_style(self->opt)); }
static PyObject *CMFontOptions_set_hint_metrics(CMFontOptions *self, PyObject *args) {
    int v; if (!PyArg_ParseTuple(args, "i", &v)) return NULL;
    cm_font_options_set_hint_metrics(self->opt, (cm_hint_metrics_t)v); Py_RETURN_NONE; }
static PyObject *CMFontOptions_get_hint_metrics(CMFontOptions *self, PyObject *Py_UNUSED(i)) {
    return PyLong_FromLong((long)cm_font_options_get_hint_metrics(self->opt)); }
static PyObject *CMFontOptions_set_variations(CMFontOptions *self, PyObject *args) {
    const char *v; if (!PyArg_ParseTuple(args, "z", &v)) return NULL;
    cm_font_options_set_variations(self->opt, v); Py_RETURN_NONE; }
static PyObject *CMFontOptions_get_variations(CMFontOptions *self, PyObject *Py_UNUSED(i)) {
    const char *v = cm_font_options_get_variations(self->opt);
    if (!v) Py_RETURN_NONE; return PyUnicode_FromString(v); }
static PyObject *CMFontOptions_richcompare(PyObject *a, PyObject *b, int op) {
    if ((op != Py_EQ && op != Py_NE) ||
        !PyObject_TypeCheck(a, &CMFontOptionsType) || !PyObject_TypeCheck(b, &CMFontOptionsType))
        Py_RETURN_NOTIMPLEMENTED;
    int eq = cm_font_options_equal(((CMFontOptions *)a)->opt, ((CMFontOptions *)b)->opt);
    if (op == Py_NE) eq = !eq;
    return PyBool_FromLong(eq);
}
static PyMethodDef CMFontOptions_methods[] = {
    {"copy",               (PyCFunction)CMFontOptions_copy,               METH_NOARGS,  "copy() -> FontOptions"},
    {"merge",              (PyCFunction)CMFontOptions_merge,              METH_O,       "merge(FontOptions)"},
    {"hash",               (PyCFunction)CMFontOptions_hash,               METH_NOARGS,  "hash() -> int"},
    {"status",             (PyCFunction)CMFontOptions_status,             METH_NOARGS,  "status() -> Status int"},
    {"set_antialias",      (PyCFunction)CMFontOptions_set_antialias,      METH_VARARGS, "set_antialias(Antialias)"},
    {"get_antialias",      (PyCFunction)CMFontOptions_get_antialias,      METH_NOARGS,  "get_antialias() -> Antialias"},
    {"set_subpixel_order", (PyCFunction)CMFontOptions_set_subpixel_order, METH_VARARGS, "set_subpixel_order(SubpixelOrder)"},
    {"get_subpixel_order", (PyCFunction)CMFontOptions_get_subpixel_order, METH_NOARGS,  "get_subpixel_order() -> SubpixelOrder"},
    {"set_hint_style",     (PyCFunction)CMFontOptions_set_hint_style,     METH_VARARGS, "set_hint_style(HintStyle)"},
    {"get_hint_style",     (PyCFunction)CMFontOptions_get_hint_style,     METH_NOARGS,  "get_hint_style() -> HintStyle"},
    {"set_hint_metrics",   (PyCFunction)CMFontOptions_set_hint_metrics,   METH_VARARGS, "set_hint_metrics(HintMetrics)"},
    {"get_hint_metrics",   (PyCFunction)CMFontOptions_get_hint_metrics,   METH_NOARGS,  "get_hint_metrics() -> HintMetrics"},
    {"set_variations",     (PyCFunction)CMFontOptions_set_variations,     METH_VARARGS, "set_variations(str|None)"},
    {"get_variations",     (PyCFunction)CMFontOptions_get_variations,     METH_NOARGS,  "get_variations() -> str|None"},
    {NULL}
};
static PyTypeObject CMFontOptionsType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "cairo_metal.FontOptions",
    .tp_basicsize = sizeof(CMFontOptions),
    .tp_flags = Py_TPFLAGS_DEFAULT | Py_TPFLAGS_BASETYPE,
    .tp_doc = "Font rendering options (cm_font_options_t).",
    .tp_new = PyType_GenericNew,
    .tp_init = (initproc)CMFontOptions_init,
    .tp_dealloc = (destructor)CMFontOptions_dealloc,
    .tp_methods = CMFontOptions_methods,
    .tp_richcompare = CMFontOptions_richcompare,
};

/* ===========================================================================
 * FontFace (base) + ToyFontFace  (cm_font_face_t)
 * =========================================================================== */
typedef struct {
    PyObject_HEAD
    cm_font_face_t *face;
    int             owns;
} CMFontFace;

static void CMFontFace_dealloc(CMFontFace *self) {
    if (self->face && self->owns) cm_font_face_destroy(self->face);
    self->face = NULL; Py_TYPE(self)->tp_free((PyObject *)self); }
static PyObject *wrap_font_face(cm_font_face_t *ff, int owns) {
    if (!ff) {
        if (cm_raise_if_error(cm_last_status()) < 0) return NULL;
        Py_RETURN_NONE;
    }
    PyTypeObject *t = (cm_font_face_get_type(ff) == CM_FONT_TYPE_TOY)
                      ? &CMToyFontFaceType : &CMFontFaceType;
    CMFontFace *o = (CMFontFace *)t->tp_alloc(t, 0);
    if (!o) { if (owns) cm_font_face_destroy(ff); return NULL; }
    o->face = ff; o->owns = owns;
    return (PyObject *)o;
}
static PyObject *CMFontFace_get_type(CMFontFace *self, PyObject *Py_UNUSED(i)) {
    return PyLong_FromLong((long)cm_font_face_get_type(self->face)); }
static PyObject *CMFontFace_status(CMFontFace *self, PyObject *Py_UNUSED(i)) {
    return PyLong_FromLong(cm_to_cairo_status(cm_font_face_status(self->face))); }
static PyMethodDef CMFontFace_methods[] = {
    {"get_type", (PyCFunction)CMFontFace_get_type, METH_NOARGS, "get_type() -> FontType"},
    {"status",   (PyCFunction)CMFontFace_status,   METH_NOARGS, "status() -> Status int"},
    {NULL}
};
static PyTypeObject CMFontFaceType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "cairo_metal.FontFace",
    .tp_basicsize = sizeof(CMFontFace),
    .tp_flags = Py_TPFLAGS_DEFAULT | Py_TPFLAGS_BASETYPE,
    .tp_doc = "Base font face (cm_font_face_t). Abstract: cannot be instantiated.",
    .tp_new = cm_abstract_new,   /* abstract base: TypeError on direct construct */
    .tp_dealloc = (destructor)CMFontFace_dealloc,
    .tp_methods = CMFontFace_methods,
};

/* ToyFontFace(family, slant=FONT_SLANT_NORMAL, weight=FONT_WEIGHT_NORMAL) */
static int CMToyFontFace_init(CMFontFace *self, PyObject *args, PyObject *kwds) {
    const char *family; int slant = CM_FONT_SLANT_NORMAL, weight = CM_FONT_WEIGHT_NORMAL;
    if (!PyArg_ParseTuple(args, "s|ii", &family, &slant, &weight)) return -1;
    self->face = cm_toy_font_face_create(family, (cm_font_slant_t)slant, (cm_font_weight_t)weight);
    if (!self->face) { PyErr_SetString(CairoError, "cm_toy_font_face_create failed"); return -1; }
    self->owns = 1;
    return 0;
}
static PyObject *CMToyFontFace_get_family(CMFontFace *self, PyObject *Py_UNUSED(i)) {
    const char *f = cm_toy_font_face_get_family(self->face);
    return PyUnicode_FromString(f ? f : ""); }
static PyObject *CMToyFontFace_get_slant(CMFontFace *self, PyObject *Py_UNUSED(i)) {
    return PyLong_FromLong((long)cm_toy_font_face_get_slant(self->face)); }
static PyObject *CMToyFontFace_get_weight(CMFontFace *self, PyObject *Py_UNUSED(i)) {
    return PyLong_FromLong((long)cm_toy_font_face_get_weight(self->face)); }
static PyMethodDef CMToyFontFace_methods[] = {
    {"get_family", (PyCFunction)CMToyFontFace_get_family, METH_NOARGS, "get_family() -> str"},
    {"get_slant",  (PyCFunction)CMToyFontFace_get_slant,  METH_NOARGS, "get_slant() -> FontSlant"},
    {"get_weight", (PyCFunction)CMToyFontFace_get_weight, METH_NOARGS, "get_weight() -> FontWeight"},
    {NULL}
};
static PyTypeObject CMToyFontFaceType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "cairo_metal.ToyFontFace",
    .tp_basicsize = sizeof(CMFontFace),
    .tp_flags = Py_TPFLAGS_DEFAULT | Py_TPFLAGS_BASETYPE,
    .tp_doc = "Toy font face.",
    .tp_base = &CMFontFaceType,
    .tp_new = PyType_GenericNew,
    .tp_init = (initproc)CMToyFontFace_init,
    .tp_methods = CMToyFontFace_methods,
};

/* ===========================================================================
 * ScaledFont  (cm_scaled_font_t)
 * =========================================================================== */
typedef struct {
    PyObject_HEAD
    cm_scaled_font_t *sf;
} CMScaledFont;

static void CMScaledFont_dealloc(CMScaledFont *self) {
    if (self->sf) { cm_scaled_font_destroy(self->sf); self->sf = NULL; }
    Py_TYPE(self)->tp_free((PyObject *)self); }
static PyObject *wrap_scaled_font(cm_scaled_font_t *sf) {
    if (!sf) {
        if (cm_raise_if_error(cm_last_status()) < 0) return NULL;
        Py_RETURN_NONE;
    }
    CMScaledFont *o = (CMScaledFont *)CMScaledFontType.tp_alloc(&CMScaledFontType, 0);
    if (!o) { cm_scaled_font_destroy(sf); return NULL; }
    o->sf = sf; return (PyObject *)o;
}
/* ScaledFont(font_face, font_matrix, ctm, font_options) */
static int CMScaledFont_init(CMScaledFont *self, PyObject *args, PyObject *kwds) {
    PyObject *ff, *fm, *ctm, *opt;
    if (!PyArg_ParseTuple(args, "O!O!O!O!",
            &CMFontFaceType, &ff, &CMMatrixType, &fm,
            &CMMatrixType, &ctm, &CMFontOptionsType, &opt)) return -1;
    self->sf = cm_scaled_font_create(((CMFontFace *)ff)->face,
                                     &((CMMatrix *)fm)->m, &((CMMatrix *)ctm)->m,
                                     ((CMFontOptions *)opt)->opt);
    if (!self->sf) { PyErr_SetString(CairoError, "cm_scaled_font_create failed"); return -1; }
    return 0;
}
static PyObject *CMScaledFont_get_type(CMScaledFont *self, PyObject *Py_UNUSED(i)) {
    return PyLong_FromLong((long)cm_scaled_font_get_type(self->sf)); }
static PyObject *CMScaledFont_status(CMScaledFont *self, PyObject *Py_UNUSED(i)) {
    return PyLong_FromLong(cm_to_cairo_status(cm_scaled_font_status(self->sf))); }
static PyObject *CMScaledFont_get_font_face(CMScaledFont *self, PyObject *Py_UNUSED(i)) {
    cm_font_face_t *ff = cm_scaled_font_get_font_face(self->sf);
    return wrap_font_face(cm_font_face_reference(ff), 1); }
static PyObject *CMScaledFont_get_font_matrix(CMScaledFont *self, PyObject *Py_UNUSED(i)) {
    cm_matrix_t m; cm_scaled_font_get_font_matrix(self->sf, &m); return matrix_from_cm(&m); }
static PyObject *CMScaledFont_get_ctm(CMScaledFont *self, PyObject *Py_UNUSED(i)) {
    cm_matrix_t m; cm_scaled_font_get_ctm(self->sf, &m); return matrix_from_cm(&m); }
static PyObject *CMScaledFont_get_scale_matrix(CMScaledFont *self, PyObject *Py_UNUSED(i)) {
    cm_matrix_t m; cm_scaled_font_get_scale_matrix(self->sf, &m); return matrix_from_cm(&m); }
static PyObject *CMScaledFont_get_font_options(CMScaledFont *self, PyObject *Py_UNUSED(i)) {
    cm_font_options_t *o = cm_font_options_create();
    if (!o) { PyErr_SetString(CairoError, "cm_font_options_create failed"); return NULL; }
    cm_scaled_font_get_font_options(self->sf, o);
    return wrap_font_options(o); }
static PyObject *CMScaledFont_extents(CMScaledFont *self, PyObject *Py_UNUSED(i)) {
    cm_font_extents_t e; cm_scaled_font_extents(self->sf, &e);
    return Py_BuildValue("(ddddd)", e.ascent, e.descent, e.height, e.max_x_advance, e.max_y_advance); }
static PyObject *CMScaledFont_text_extents(CMScaledFont *self, PyObject *args) {
    const char *utf8; if (!PyArg_ParseTuple(args, "s", &utf8)) return NULL;
    cm_text_extents_t e; cm_scaled_font_text_extents(self->sf, utf8, &e);
    return Py_BuildValue("(dddddd)", e.x_bearing, e.y_bearing, e.width, e.height, e.x_advance, e.y_advance); }
/* glyph_extents(glyphs) -> TextExtents 6-tuple.  glyphs is a sequence of
 * (index, x, y).  Marshalled inline (the glyph helper is defined later in the
 * Context section, so we duplicate the tiny parse here to keep file order). */
static PyObject *CMScaledFont_glyph_extents(CMScaledFont *self, PyObject *args) {
    PyObject *seq; if (!PyArg_ParseTuple(args, "O", &seq)) return NULL;
    PyObject *fast = PySequence_Fast(seq, "glyphs must be a sequence of (index, x, y)");
    if (!fast) return NULL;
    Py_ssize_t n = PySequence_Fast_GET_SIZE(fast);
    cm_text_extents_t e; memset(&e, 0, sizeof(e));
    if (n == 0) { Py_DECREF(fast); return Py_BuildValue("(dddddd)", 0.,0.,0.,0.,0.,0.); }
    cm_glyph_t *g = (cm_glyph_t *)malloc((size_t)n * sizeof(cm_glyph_t));
    if (!g) { Py_DECREF(fast); return PyErr_NoMemory(); }
    for (Py_ssize_t i = 0; i < n; ++i) {
        PyObject *it = PySequence_Fast_GET_ITEM(fast, i);
        if (!PyArg_ParseTuple(it, "kdd", &g[i].index, &g[i].x, &g[i].y)) {
            PyErr_Clear();
            PyErr_Format(PyExc_TypeError, "glyph %zd must be a 3-tuple (index, x, y)", i);
            free(g); Py_DECREF(fast); return NULL;
        }
    }
    Py_DECREF(fast);
    cm_scaled_font_glyph_extents(self->sf, g, (int)n, &e);
    free(g);
    return Py_BuildValue("(dddddd)", e.x_bearing, e.y_bearing, e.width, e.height, e.x_advance, e.y_advance); }
/* text_to_glyphs(x, y, utf8, with_clusters=True) -> list of (index, x, y)
 *   OR (glyphs, clusters, cluster_flags) when with_clusters is True (the pycairo
 *   default).  The engine's shaper returns glyphs only (clusters are NULL -- a
 *   valid cairo result when the back-mapping was not produced); we therefore
 *   return an EMPTY cluster list + flags 0 in the tupled form. */
static PyObject *CMScaledFont_text_to_glyphs(CMScaledFont *self, PyObject *args) {
    double x, y; const char *utf8; Py_ssize_t utf8_len;
    int with_clusters = 1;
    if (!PyArg_ParseTuple(args, "dds#|p", &x, &y, &utf8, &utf8_len, &with_clusters))
        return NULL;
    cm_glyph_t *glyphs = NULL; int ng = 0;
    cm_text_cluster_t *clusters = NULL; int nc = 0;
    cm_text_cluster_flags_t cflags = (cm_text_cluster_flags_t)0;
    cm_status_t st = cm_scaled_font_text_to_glyphs(self->sf, x, y, utf8, (int)utf8_len,
                                                   &glyphs, &ng, &clusters, &nc, &cflags);
    if (cm_raise_if_error(st) < 0) {
        cm_glyph_free(glyphs); cm_text_cluster_free(clusters); return NULL;
    }
    PyObject *glist = PyList_New(ng);
    if (!glist) { cm_glyph_free(glyphs); cm_text_cluster_free(clusters); return NULL; }
    for (int i = 0; i < ng; ++i) {
        PyObject *t = Py_BuildValue("(kdd)", glyphs[i].index, glyphs[i].x, glyphs[i].y);
        if (!t) { Py_DECREF(glist); cm_glyph_free(glyphs); cm_text_cluster_free(clusters); return NULL; }
        PyList_SET_ITEM(glist, i, t);  /* steals t */
    }
    PyObject *result;
    if (with_clusters) {
        PyObject *clist = PyList_New(nc);
        if (!clist) { Py_DECREF(glist); cm_glyph_free(glyphs); cm_text_cluster_free(clusters); return NULL; }
        for (int i = 0; i < nc; ++i) {
            PyObject *t = Py_BuildValue("(ii)", clusters[i].num_bytes, clusters[i].num_glyphs);
            if (!t) { Py_DECREF(clist); Py_DECREF(glist); cm_glyph_free(glyphs); cm_text_cluster_free(clusters); return NULL; }
            PyList_SET_ITEM(clist, i, t);
        }
        result = Py_BuildValue("(NNi)", glist, clist, (int)cflags);  /* steals glist, clist */
    } else {
        result = glist;  /* glyphs-only form */
    }
    cm_glyph_free(glyphs); cm_text_cluster_free(clusters);
    return result; }
static PyMethodDef CMScaledFont_methods[] = {
    {"get_type",          (PyCFunction)CMScaledFont_get_type,          METH_NOARGS, "get_type() -> FontType"},
    {"status",            (PyCFunction)CMScaledFont_status,            METH_NOARGS, "status() -> Status int"},
    {"get_font_face",     (PyCFunction)CMScaledFont_get_font_face,     METH_NOARGS, "get_font_face() -> FontFace"},
    {"get_font_matrix",   (PyCFunction)CMScaledFont_get_font_matrix,   METH_NOARGS, "get_font_matrix() -> Matrix"},
    {"get_ctm",           (PyCFunction)CMScaledFont_get_ctm,           METH_NOARGS, "get_ctm() -> Matrix"},
    {"get_scale_matrix",  (PyCFunction)CMScaledFont_get_scale_matrix,  METH_NOARGS, "get_scale_matrix() -> Matrix"},
    {"get_font_options",  (PyCFunction)CMScaledFont_get_font_options,  METH_NOARGS, "get_font_options() -> FontOptions"},
    {"extents",           (PyCFunction)CMScaledFont_extents,           METH_NOARGS, "extents() -> (ascent, descent, height, max_x_advance, max_y_advance)"},
    {"text_extents",      (PyCFunction)CMScaledFont_text_extents,      METH_VARARGS,"text_extents(text) -> (x_bearing, y_bearing, width, height, x_advance, y_advance)"},
    {"glyph_extents",     (PyCFunction)CMScaledFont_glyph_extents,     METH_VARARGS,"glyph_extents(glyphs) -> (x_bearing, y_bearing, width, height, x_advance, y_advance)"},
    {"text_to_glyphs",    (PyCFunction)CMScaledFont_text_to_glyphs,    METH_VARARGS,"text_to_glyphs(x, y, text, with_clusters=True) -> glyphs or (glyphs, clusters, flags)"},
    {NULL}
};
static PyTypeObject CMScaledFontType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "cairo_metal.ScaledFont",
    .tp_basicsize = sizeof(CMScaledFont),
    .tp_flags = Py_TPFLAGS_DEFAULT | Py_TPFLAGS_BASETYPE,
    .tp_doc = "Font scaled to a size + CTM (cm_scaled_font_t).",
    .tp_new = PyType_GenericNew,
    .tp_init = (initproc)CMScaledFont_init,
    .tp_dealloc = (destructor)CMScaledFont_dealloc,
    .tp_methods = CMScaledFont_methods,
};

/* ===========================================================================
 * Path  (cm_path_data_t) -- the result of Context.copy_path / copy_path_flat
 * ---------------------------------------------------------------------------
 * pycairo's Path is an opaque, ITERABLE object whose iteration yields
 * (type, point_tuple) pairs, where point_tuple has the cairo-canonical arity:
 *     (PATH_MOVE_TO,   (x, y))
 *     (PATH_LINE_TO,   (x, y))
 *     (PATH_CURVE_TO,  (x1, y1, x2, y2, x3, y3))
 *     (PATH_CLOSE_PATH, ())
 * We back it by the engine's cm_path_data_t (an array of {type, points[6]}).
 * __iter__ returns a fresh CMPathIter so a Path can be iterated repeatedly,
 * exactly like pycairo (which re-walks its data each time).
 * =========================================================================== */
typedef struct {
    PyObject_HEAD
    cm_path_data_t *data;        /* owned; freed in dealloc                    */
} CMPath;

typedef struct {
    PyObject_HEAD
    PyObject *path;              /* strong ref to the CMPath being iterated    */
    int       index;            /* next element to yield                       */
} CMPathIter;

static void CMPath_dealloc(CMPath *self) {
    if (self->data) { cm_path_data_destroy(self->data); self->data = NULL; }
    Py_TYPE(self)->tp_free((PyObject *)self);
}

/* Build a (type, points-tuple) pair for element i, with cairo-canonical arity. */
static PyObject *cm_path_element_pair(const cm_path_element_t *e) {
    PyObject *pts;
    switch (e->type) {
        case CM_PATH_MOVE_TO:
        case CM_PATH_LINE_TO:
            pts = Py_BuildValue("(dd)", e->points[0], e->points[1]);
            break;
        case CM_PATH_CURVE_TO:
            pts = Py_BuildValue("(dddddd)", e->points[0], e->points[1],
                                            e->points[2], e->points[3],
                                            e->points[4], e->points[5]);
            break;
        case CM_PATH_CLOSE_PATH:
        default:
            pts = PyTuple_New(0);
            break;
    }
    if (!pts) return NULL;
    return Py_BuildValue("(iN)", (int)e->type, pts);  /* steals pts */
}

static Py_ssize_t CMPath_length(CMPath *self) {
    return (self->data && self->data->elements) ? self->data->num_elements : 0;
}

static PyObject *CMPathIter_new_for(PyObject *path);   /* fwd */

static PyObject *CMPath_iter(CMPath *self) {
    return CMPathIter_new_for((PyObject *)self);
}

static PySequenceMethods CMPath_as_sequence = {
    .sq_length = (lenfunc)CMPath_length,
};

static PyTypeObject CMPathType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "cairo_metal.Path",
    .tp_basicsize = sizeof(CMPath),
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_doc = "Copied path (cm_path_data_t). Iterable: yields (type, points).",
    .tp_new = cm_abstract_new,   /* only produced by copy_path(); not user-built */
    .tp_dealloc = (destructor)CMPath_dealloc,
    .tp_iter = (getiterfunc)CMPath_iter,
    .tp_as_sequence = &CMPath_as_sequence,
};

static void CMPathIter_dealloc(CMPathIter *self) {
    Py_XDECREF(self->path);
    Py_TYPE(self)->tp_free((PyObject *)self);
}
static PyObject *CMPathIter_iternext(CMPathIter *self) {
    CMPath *p = (CMPath *)self->path;
    if (!p || !p->data || !p->data->elements) return NULL;  /* StopIteration */
    if (self->index >= p->data->num_elements) return NULL;
    PyObject *pair = cm_path_element_pair(&p->data->elements[self->index]);
    if (!pair) return NULL;
    self->index++;
    return pair;
}
static PyObject *CMPathIter_selfiter(PyObject *self) { Py_INCREF(self); return self; }

static PyTypeObject CMPathIterType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "cairo_metal.PathIterator",
    .tp_basicsize = sizeof(CMPathIter),
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_doc = "Iterator over a Path's elements.",
    .tp_new = cm_abstract_new,
    .tp_dealloc = (destructor)CMPathIter_dealloc,
    .tp_iter = (getiterfunc)CMPathIter_selfiter,
    .tp_iternext = (iternextfunc)CMPathIter_iternext,
};

static PyObject *CMPathIter_new_for(PyObject *path) {
    CMPathIter *it = PyObject_New(CMPathIter, &CMPathIterType);
    if (!it) return NULL;
    Py_INCREF(path);
    it->path = path;
    it->index = 0;
    return (PyObject *)it;
}

/* Wrap an owned cm_path_data_t* in a Python Path (steals the reference).  On a
 * NULL data or a non-SUCCESS status, raises and destroys the data. */
static PyObject *wrap_path_data(cm_path_data_t *data) {
    if (!data) { PyErr_NoMemory(); return NULL; }
    if (data->status != CM_STATUS_SUCCESS) {
        cm_raise_if_error(data->status);
        if (!PyErr_Occurred())
            PyErr_SetString(CairoError, "cairo_metal: copy_path failed");
        cm_path_data_destroy(data);
        return NULL;
    }
    CMPath *p = PyObject_New(CMPath, &CMPathType);
    if (!p) { cm_path_data_destroy(data); return NULL; }
    p->data = data;
    return (PyObject *)p;
}

/* ===========================================================================
 * Context  (cm_context_t) -- the full drawing surface
 * =========================================================================== */
typedef struct {
    PyObject_HEAD
    cm_context_t *ctx;
    PyObject     *surface;   /* keeps the target Surface alive */
    PyObject     *source;    /* current source Pattern (keeps it alive) or NULL */
} CMContext;

static void
CMContext_dealloc(CMContext *self)
{
    if (self->ctx) { cm_context_destroy(self->ctx); self->ctx = NULL; }
    Py_XDECREF(self->source);
    Py_XDECREF(self->surface);
    Py_TYPE(self)->tp_free((PyObject *)self);
}

static int
CMContext_init(CMContext *self, PyObject *args, PyObject *kwds)
{
    PyObject *surf;
    if (!PyArg_ParseTuple(args, "O!", &CMSurfaceType, &surf)) return -1;
    CMSurface *s = (CMSurface *)surf;
    if (!s->surf) { PyErr_SetString(CairoError, "cairo_metal: dead surface"); return -1; }
    self->ctx = cm_context_create(s->surf);
    if (!self->ctx) {
        cm_raise_if_error(cm_last_status());
        if (!PyErr_Occurred()) PyErr_SetString(CairoError, "cm_context_create failed");
        return -1;
    }
    Py_INCREF(surf); self->surface = surf; self->source = NULL;
    return 0;
}

/* -------- macro helpers for the many uniform forwarders -------- */
#define CTX0(NAME, CALL) \
static PyObject *NAME(CMContext *self, PyObject *Py_UNUSED(i)) { \
    CALL(self->ctx); Py_RETURN_NONE; }
#define CTX0_CHK(NAME, CALL) \
static PyObject *NAME(CMContext *self, PyObject *Py_UNUSED(i)) { \
    CALL(self->ctx); if (cm_check_ctx(self->ctx) < 0) return NULL; Py_RETURN_NONE; }
#define CTX_1D(NAME, CALL) \
static PyObject *NAME(CMContext *self, PyObject *args) { \
    double a; if (!PyArg_ParseTuple(args, "d", &a)) return NULL; \
    CALL(self->ctx, a); Py_RETURN_NONE; }
#define CTX_2D(NAME, CALL) \
static PyObject *NAME(CMContext *self, PyObject *args) { \
    double a, b; if (!PyArg_ParseTuple(args, "dd", &a, &b)) return NULL; \
    CALL(self->ctx, a, b); Py_RETURN_NONE; }
#define CTX_GET_I(NAME, CALL) \
static PyObject *NAME(CMContext *self, PyObject *Py_UNUSED(i)) { \
    return PyLong_FromLong((long)CALL(self->ctx)); }
#define CTX_GET_D(NAME, CALL) \
static PyObject *NAME(CMContext *self, PyObject *Py_UNUSED(i)) { \
    return PyFloat_FromDouble(CALL(self->ctx)); }
#define CTX_SET_I(NAME, CALL, CTYPE) \
static PyObject *NAME(CMContext *self, PyObject *args) { \
    int v; if (!PyArg_ParseTuple(args, "i", &v)) return NULL; \
    CALL(self->ctx, (CTYPE)v); Py_RETURN_NONE; }
/* returns (x1, y1, x2, y2) from a 4-double-out cm_* query */
#define CTX_EXTENTS(NAME, CALL) \
static PyObject *NAME(CMContext *self, PyObject *Py_UNUSED(i)) { \
    double x1, y1, x2, y2; CALL(self->ctx, &x1, &y1, &x2, &y2); \
    return Py_BuildValue("(dddd)", x1, y1, x2, y2); }

/* ---- state stack ---- */
static PyObject *CMContext_save(CMContext *self, PyObject *Py_UNUSED(i)) {
    cm_save(self->ctx); Py_RETURN_NONE; }
static PyObject *CMContext_restore(CMContext *self, PyObject *Py_UNUSED(i)) {
    cm_restore(self->ctx); if (cm_check_ctx(self->ctx) < 0) return NULL; Py_RETURN_NONE; }

/* ---- compositing state ---- */
CTX_SET_I(CMContext_set_operator, cm_set_operator, cm_operator_t)
CTX_GET_I(CMContext_get_operator, cm_get_operator)
CTX_SET_I(CMContext_set_antialias, cm_set_antialias, cm_antialias_t)
CTX_GET_I(CMContext_get_antialias, cm_get_antialias)
CTX_1D(CMContext_set_tolerance, cm_set_tolerance)
CTX_GET_D(CMContext_get_tolerance, cm_get_tolerance)

/* dash: set_dash(dashes_seq, offset=0.0); get_dash() -> (dashes, offset) */
static PyObject *CMContext_set_dash(CMContext *self, PyObject *args) {
    PyObject *seq; double offset = 0.0;
    if (!PyArg_ParseTuple(args, "O|d", &seq, &offset)) return NULL;
    PyObject *fast = PySequence_Fast(seq, "set_dash expects a sequence of floats");
    if (!fast) return NULL;
    Py_ssize_t n = PySequence_Fast_GET_SIZE(fast);
    double *d = NULL;
    if (n > 0) {
        d = PyMem_Malloc(sizeof(double) * n);
        if (!d) { Py_DECREF(fast); return PyErr_NoMemory(); }
        for (Py_ssize_t i = 0; i < n; ++i) {
            d[i] = PyFloat_AsDouble(PySequence_Fast_GET_ITEM(fast, i));
            if (PyErr_Occurred()) { PyMem_Free(d); Py_DECREF(fast); return NULL; }
        }
    }
    Py_DECREF(fast);
    cm_set_dash(self->ctx, d, (int)n, offset);
    PyMem_Free(d);
    if (cm_check_ctx(self->ctx) < 0) return NULL;
    Py_RETURN_NONE;
}
static PyObject *CMContext_get_dash(CMContext *self, PyObject *Py_UNUSED(i)) {
    int n = cm_get_dash_count(self->ctx);
    double offset = 0.0;
    PyObject *list = PyList_New(n);
    if (!list) return NULL;
    if (n > 0) {
        double *d = PyMem_Malloc(sizeof(double) * n);
        if (!d) { Py_DECREF(list); return PyErr_NoMemory(); }
        cm_get_dash(self->ctx, d, &offset);
        for (int i = 0; i < n; ++i) {
            PyObject *f = PyFloat_FromDouble(d[i]);
            if (!f) { PyMem_Free(d); Py_DECREF(list); return NULL; }
            PyList_SET_ITEM(list, i, f);
        }
        PyMem_Free(d);
    } else {
        cm_get_dash(self->ctx, NULL, &offset);
    }
    return Py_BuildValue("(Nd)", list, offset);
}
static PyObject *CMContext_get_dash_count(CMContext *self, PyObject *Py_UNUSED(i)) {
    return PyLong_FromLong(cm_get_dash_count(self->ctx)); }

/* ---- transform ---- */
static PyObject *CMContext_set_matrix(CMContext *self, PyObject *args) {
    PyObject *mo; if (!PyArg_ParseTuple(args, "O", &mo)) return NULL;
    cm_matrix_t m; if (matrix_as_cm(mo, &m) < 0) return NULL;
    cm_set_matrix(self->ctx, &m); Py_RETURN_NONE; }
static PyObject *CMContext_get_matrix(CMContext *self, PyObject *Py_UNUSED(i)) {
    cm_matrix_t m; cm_get_matrix(self->ctx, &m); return matrix_from_cm(&m); }
CTX0(CMContext_identity_matrix, cm_identity_matrix)
CTX_2D(CMContext_scale, cm_scale)
CTX_2D(CMContext_translate, cm_translate)
CTX_1D(CMContext_rotate, cm_rotate)
static PyObject *CMContext_transform(CMContext *self, PyObject *args) {
    PyObject *mo; if (!PyArg_ParseTuple(args, "O", &mo)) return NULL;
    cm_matrix_t m; if (matrix_as_cm(mo, &m) < 0) return NULL;
    cm_transform(self->ctx, &m); Py_RETURN_NONE; }
static PyObject *CMContext_user_to_device(CMContext *self, PyObject *args) {
    double x, y; if (!PyArg_ParseTuple(args, "dd", &x, &y)) return NULL;
    cm_user_to_device(self->ctx, &x, &y); return Py_BuildValue("(dd)", x, y); }
static PyObject *CMContext_user_to_device_distance(CMContext *self, PyObject *args) {
    double x, y; if (!PyArg_ParseTuple(args, "dd", &x, &y)) return NULL;
    cm_user_to_device_distance(self->ctx, &x, &y); return Py_BuildValue("(dd)", x, y); }
static PyObject *CMContext_device_to_user(CMContext *self, PyObject *args) {
    double x, y; if (!PyArg_ParseTuple(args, "dd", &x, &y)) return NULL;
    cm_device_to_user(self->ctx, &x, &y); return Py_BuildValue("(dd)", x, y); }
static PyObject *CMContext_device_to_user_distance(CMContext *self, PyObject *args) {
    double x, y; if (!PyArg_ParseTuple(args, "dd", &x, &y)) return NULL;
    cm_device_to_user_distance(self->ctx, &x, &y); return Py_BuildValue("(dd)", x, y); }

/* ---- path construction ---- */
CTX0(CMContext_new_path, cm_new_path)
CTX0(CMContext_new_sub_path, cm_new_sub_path)
CTX0(CMContext_close_path, cm_close_path)
CTX_2D(CMContext_move_to, cm_move_to)
CTX_2D(CMContext_line_to, cm_line_to)
static PyObject *CMContext_curve_to(CMContext *self, PyObject *args) {
    double x1, y1, x2, y2, x3, y3;
    if (!PyArg_ParseTuple(args, "dddddd", &x1, &y1, &x2, &y2, &x3, &y3)) return NULL;
    cm_curve_to(self->ctx, x1, y1, x2, y2, x3, y3); Py_RETURN_NONE; }
static PyObject *CMContext_rel_move_to(CMContext *self, PyObject *args) {
    double dx, dy; if (!PyArg_ParseTuple(args, "dd", &dx, &dy)) return NULL;
    cm_rel_move_to(self->ctx, dx, dy); if (cm_check_ctx(self->ctx) < 0) return NULL; Py_RETURN_NONE; }
static PyObject *CMContext_rel_line_to(CMContext *self, PyObject *args) {
    double dx, dy; if (!PyArg_ParseTuple(args, "dd", &dx, &dy)) return NULL;
    cm_rel_line_to(self->ctx, dx, dy); if (cm_check_ctx(self->ctx) < 0) return NULL; Py_RETURN_NONE; }
static PyObject *CMContext_rel_curve_to(CMContext *self, PyObject *args) {
    double dx1, dy1, dx2, dy2, dx3, dy3;
    if (!PyArg_ParseTuple(args, "dddddd", &dx1, &dy1, &dx2, &dy2, &dx3, &dy3)) return NULL;
    cm_rel_curve_to(self->ctx, dx1, dy1, dx2, dy2, dx3, dy3);
    if (cm_check_ctx(self->ctx) < 0) return NULL; Py_RETURN_NONE; }
static PyObject *CMContext_rectangle(CMContext *self, PyObject *args) {
    double x, y, w, h; if (!PyArg_ParseTuple(args, "dddd", &x, &y, &w, &h)) return NULL;
    cm_rectangle(self->ctx, x, y, w, h); Py_RETURN_NONE; }
static PyObject *CMContext_arc(CMContext *self, PyObject *args) {
    double xc, yc, r, a1, a2;
    if (!PyArg_ParseTuple(args, "ddddd", &xc, &yc, &r, &a1, &a2)) return NULL;
    cm_arc(self->ctx, xc, yc, r, a1, a2); Py_RETURN_NONE; }
static PyObject *CMContext_arc_negative(CMContext *self, PyObject *args) {
    double xc, yc, r, a1, a2;
    if (!PyArg_ParseTuple(args, "ddddd", &xc, &yc, &r, &a1, &a2)) return NULL;
    cm_arc_negative(self->ctx, xc, yc, r, a1, a2); Py_RETURN_NONE; }
static PyObject *CMContext_has_current_point(CMContext *self, PyObject *Py_UNUSED(i)) {
    return PyBool_FromLong(cm_has_current_point(self->ctx)); }
static PyObject *CMContext_get_current_point(CMContext *self, PyObject *Py_UNUSED(i)) {
    double x = 0, y = 0; cm_get_current_point(self->ctx, &x, &y);
    return Py_BuildValue("(dd)", x, y); }
CTX_EXTENTS(CMContext_path_extents, cm_path_extents)

/* copy_path / copy_path_flat -> Path (iterable of (type, points)); append_path
 * replays a Path onto the current path. */
static PyObject *CMContext_copy_path(CMContext *self, PyObject *Py_UNUSED(i)) {
    cm_path_data_t *d = cm_copy_path(self->ctx);
    PyObject *p = wrap_path_data(d);          /* steals d (or raises + frees) */
    if (!p) return NULL;
    if (cm_check_ctx(self->ctx) < 0) { Py_DECREF(p); return NULL; }
    return p;
}
static PyObject *CMContext_copy_path_flat(CMContext *self, PyObject *Py_UNUSED(i)) {
    cm_path_data_t *d = cm_copy_path_flat(self->ctx);
    PyObject *p = wrap_path_data(d);
    if (!p) return NULL;
    if (cm_check_ctx(self->ctx) < 0) { Py_DECREF(p); return NULL; }
    return p;
}
static PyObject *CMContext_append_path(CMContext *self, PyObject *args) {
    PyObject *obj;
    if (!PyArg_ParseTuple(args, "O", &obj)) return NULL;
    if (!PyObject_TypeCheck(obj, &CMPathType)) {
        PyErr_SetString(PyExc_TypeError, "append_path expects a Path");
        return NULL;
    }
    cm_append_path(self->ctx, ((CMPath *)obj)->data);
    if (cm_check_ctx(self->ctx) < 0) return NULL;
    Py_RETURN_NONE;
}

/* ---- source / paint ---- */
static PyObject *CMContext_set_source_rgba(CMContext *self, PyObject *args) {
    double r, g, b, a = 1.0;
    if (!PyArg_ParseTuple(args, "ddd|d", &r, &g, &b, &a)) return NULL;
    cm_set_source_rgba(self->ctx, r, g, b, a);
    Py_CLEAR(self->source);
    Py_RETURN_NONE; }
static PyObject *CMContext_set_source_rgb(CMContext *self, PyObject *args) {
    double r, g, b;
    if (!PyArg_ParseTuple(args, "ddd", &r, &g, &b)) return NULL;
    cm_set_source_rgba(self->ctx, r, g, b, 1.0);
    Py_CLEAR(self->source);
    Py_RETURN_NONE; }
static PyObject *CMContext_set_source(CMContext *self, PyObject *args) {
    PyObject *pat;
    if (!PyArg_ParseTuple(args, "O!", &CMPatternType, &pat)) return NULL;
    cm_set_source(self->ctx, ((CMPattern *)pat)->pat);
    Py_INCREF(pat); Py_XSETREF(self->source, pat);
    Py_RETURN_NONE; }
static PyObject *CMContext_set_source_surface(CMContext *self, PyObject *args) {
    PyObject *surf; double x = 0, y = 0;
    if (!PyArg_ParseTuple(args, "O!|dd", &CMSurfaceType, &surf, &x, &y)) return NULL;
    CMSurface *s = (CMSurface *)surf;
    if (!s->surf) { PyErr_SetString(CairoError, "cairo_metal: dead surface"); return NULL; }
    cm_set_source_surface(self->ctx, s->surf, x, y);
    /* cm_set_source_surface builds a SurfacePattern that takes its OWN lifetime
     * reference on the surface (cm_surface_reference); the surface is refcounted,
     * so the Python wrapper KEEPS its own reference (owns stays 1) -- the surface
     * survives while either is alive.  Keep the Python surface object alive as
     * `source` so the wrapper outlives the installed pattern. */
    Py_INCREF(surf); Py_XSETREF(self->source, surf);
    Py_RETURN_NONE; }
static PyObject *CMContext_get_source(CMContext *self, PyObject *Py_UNUSED(i)) {
    cm_pattern_t *p = cm_get_source(self->ctx);   /* caller owns a reference */
    return wrap_pattern(p, 1); }

/* ---- fill / stroke params ---- */
CTX_SET_I(CMContext_set_fill_rule, cm_set_fill_rule, cm_fill_rule_t)
CTX_GET_I(CMContext_get_fill_rule, cm_get_fill_rule)
CTX_1D(CMContext_set_line_width, cm_set_line_width)
CTX_GET_D(CMContext_get_line_width, cm_get_line_width)
CTX_SET_I(CMContext_set_line_join, cm_set_line_join, cm_line_join_t)
CTX_GET_I(CMContext_get_line_join, cm_get_line_join)
CTX_SET_I(CMContext_set_line_cap, cm_set_line_cap, cm_line_cap_t)
CTX_GET_I(CMContext_get_line_cap, cm_get_line_cap)
CTX_1D(CMContext_set_miter_limit, cm_set_miter_limit)
CTX_GET_D(CMContext_get_miter_limit, cm_get_miter_limit)

/* ---- fill / stroke / paint / mask ---- */
CTX0_CHK(CMContext_fill, cm_fill)
CTX0_CHK(CMContext_fill_preserve, cm_fill_preserve)
CTX0_CHK(CMContext_stroke, cm_stroke)
CTX0_CHK(CMContext_stroke_preserve, cm_stroke_preserve)
CTX0_CHK(CMContext_paint, cm_paint)
static PyObject *CMContext_paint_with_alpha(CMContext *self, PyObject *args) {
    double a; if (!PyArg_ParseTuple(args, "d", &a)) return NULL;
    cm_paint_with_alpha(self->ctx, a); if (cm_check_ctx(self->ctx) < 0) return NULL; Py_RETURN_NONE; }
static PyObject *CMContext_mask(CMContext *self, PyObject *args) {
    PyObject *pat; if (!PyArg_ParseTuple(args, "O!", &CMPatternType, &pat)) return NULL;
    cm_mask(self->ctx, ((CMPattern *)pat)->pat);
    if (cm_check_ctx(self->ctx) < 0) return NULL; Py_RETURN_NONE; }
static PyObject *CMContext_mask_surface(CMContext *self, PyObject *args) {
    PyObject *surf; double x = 0, y = 0;
    if (!PyArg_ParseTuple(args, "O!|dd", &CMSurfaceType, &surf, &x, &y)) return NULL;
    CMSurface *s = (CMSurface *)surf;
    if (!s->surf) { PyErr_SetString(CairoError, "cairo_metal: dead surface"); return NULL; }
    cm_mask_surface(self->ctx, s->surf, x, y);
    /* cm_mask_surface builds a transient SurfacePattern that takes its OWN lifetime
     * reference and drops it when destroyed; the surface is refcounted, so the
     * user's wrapper keeps owning it and the surface stays VALID after the call.
     * (Previously this nulled s->surf assuming the surface was freed -- which
     * orphaned a still-live user surface and is the BUG-5 A8-mask-reuse crash.)
     * Nothing to release here: the Python wrapper still holds its reference. */
    if (cm_check_ctx(self->ctx) < 0) return NULL; Py_RETURN_NONE; }

/* ---- clipping ---- */
CTX0(CMContext_clip, cm_clip)
CTX0(CMContext_clip_preserve, cm_clip_preserve)
CTX0(CMContext_reset_clip, cm_reset_clip)
CTX_EXTENTS(CMContext_clip_extents, cm_clip_extents)
static PyObject *CMContext_in_clip(CMContext *self, PyObject *args) {
    double x, y; if (!PyArg_ParseTuple(args, "dd", &x, &y)) return NULL;
    return PyBool_FromLong(cm_in_clip(self->ctx, x, y)); }
static PyObject *CMContext_copy_clip_rectangle_list(CMContext *self, PyObject *Py_UNUSED(i)) {
    enum { MAXR = 256 };
    cm_rectangle_t rects[MAXR]; int count = 0;
    cm_status_t st = cm_copy_clip_rectangle_list(self->ctx, rects, MAXR, &count);
    if (cm_raise_if_error(st) < 0) return NULL;
    PyObject *list = PyList_New(count);
    if (!list) return NULL;
    for (int i = 0; i < count; ++i) {
        PyObject *t = Py_BuildValue("(dddd)", rects[i].x, rects[i].y, rects[i].width, rects[i].height);
        if (!t) { Py_DECREF(list); return NULL; }
        PyList_SET_ITEM(list, i, t);
    }
    return list;
}

/* ---- groups ---- */
CTX0(CMContext_push_group, cm_push_group)
static PyObject *CMContext_push_group_with_content(CMContext *self, PyObject *args) {
    int c; if (!PyArg_ParseTuple(args, "i", &c)) return NULL;
    cm_push_group_with_content(self->ctx, (cm_content_t)c); Py_RETURN_NONE; }
static PyObject *CMContext_pop_group(CMContext *self, PyObject *Py_UNUSED(i)) {
    cm_pattern_t *p = cm_pop_group(self->ctx);   /* caller owns a reference */
    if (cm_check_ctx(self->ctx) < 0) { if (p) cm_pattern_destroy(p); return NULL; }
    return wrap_pattern(p, 1); }
static PyObject *CMContext_pop_group_to_source(CMContext *self, PyObject *Py_UNUSED(i)) {
    cm_pop_group_to_source(self->ctx);
    Py_CLEAR(self->source);   /* the source is now the popped group (C-owned) */
    if (cm_check_ctx(self->ctx) < 0) return NULL; Py_RETURN_NONE; }
static PyObject *CMContext_get_group_target(CMContext *self, PyObject *Py_UNUSED(i)) {
    cm_surface_t *s = cm_context_get_group_target(self->ctx);
    return wrap_surface(s, 0); }  /* borrowed */
static PyObject *CMContext_get_target(CMContext *self, PyObject *Py_UNUSED(i)) {
    if (self->surface) { Py_INCREF(self->surface); return self->surface; }
    return wrap_surface(cm_context_get_target(self->ctx), 0); }

/* ---- query / hit tests ---- */
CTX_EXTENTS(CMContext_fill_extents, cm_fill_extents)
CTX_EXTENTS(CMContext_stroke_extents, cm_stroke_extents)
static PyObject *CMContext_in_fill(CMContext *self, PyObject *args) {
    double x, y; if (!PyArg_ParseTuple(args, "dd", &x, &y)) return NULL;
    return PyBool_FromLong(cm_in_fill(self->ctx, x, y)); }
static PyObject *CMContext_in_stroke(CMContext *self, PyObject *args) {
    double x, y; if (!PyArg_ParseTuple(args, "dd", &x, &y)) return NULL;
    return PyBool_FromLong(cm_in_stroke(self->ctx, x, y)); }

/* ---- glyph-list marshalling (pycairo "glyph" == (index, x, y) tuple) ----
 * Convert a Python sequence of (index, x, y) into a freshly malloc'd
 * cm_glyph_t[] (binary-compatible with cairo_glyph_t).  Returns the array (which
 * the caller frees with free()) and writes the count into *out_n; on any error
 * sets a Python exception and returns NULL.  An empty sequence yields a NULL
 * array with *out_n == 0 (a valid cairo "no glyphs" run -- callers treat that as
 * a no-op, matching cairo_show_glyphs with num_glyphs == 0). */
static cm_glyph_t *
glyphs_as_cm(PyObject *seq, int *out_n)
{
    *out_n = 0;
    PyObject *fast = PySequence_Fast(seq, "glyphs must be a sequence of (index, x, y)");
    if (!fast) return NULL;
    Py_ssize_t n = PySequence_Fast_GET_SIZE(fast);
    if (n == 0) { Py_DECREF(fast); return NULL; }   /* empty run: NULL + n==0 */
    cm_glyph_t *g = (cm_glyph_t *)malloc((size_t)n * sizeof(cm_glyph_t));
    if (!g) { Py_DECREF(fast); PyErr_NoMemory(); return NULL; }
    for (Py_ssize_t i = 0; i < n; ++i) {
        PyObject *item = PySequence_Fast_GET_ITEM(fast, i);   /* borrowed */
        unsigned long index; double x, y;
        if (!PyArg_ParseTuple(item, "kdd", &index, &x, &y)) {
            /* Re-issue a clearer message than the bare ParseTuple one. */
            PyErr_Clear();
            PyErr_Format(PyExc_TypeError,
                "glyph %zd must be a 3-tuple (index, x, y)", i);
            free(g); Py_DECREF(fast); return NULL;
        }
        g[i].index = index; g[i].x = x; g[i].y = y;
    }
    Py_DECREF(fast);
    *out_n = (int)n;
    return g;
}

/* Build the 6-tuple pycairo TextExtents (x_bearing, y_bearing, width, height,
 * x_advance, y_advance) from a cm_text_extents_t. */
static PyObject *
text_extents_tuple(const cm_text_extents_t *e)
{
    return Py_BuildValue("(dddddd)", e->x_bearing, e->y_bearing, e->width,
                         e->height, e->x_advance, e->y_advance);
}

/* ---- font / text ---- */
static PyObject *CMContext_select_font_face(CMContext *self, PyObject *args) {
    const char *family; int slant = CM_FONT_SLANT_NORMAL, weight = CM_FONT_WEIGHT_NORMAL;
    if (!PyArg_ParseTuple(args, "s|ii", &family, &slant, &weight)) return NULL;
    cm_select_font_face(self->ctx, family, (cm_font_slant_t)slant, (cm_font_weight_t)weight);
    Py_RETURN_NONE; }
CTX_1D(CMContext_set_font_size, cm_set_font_size)
static PyObject *CMContext_set_font_matrix(CMContext *self, PyObject *args) {
    PyObject *mo; if (!PyArg_ParseTuple(args, "O", &mo)) return NULL;
    cm_matrix_t m; if (matrix_as_cm(mo, &m) < 0) return NULL;
    cm_set_font_matrix(self->ctx, &m); Py_RETURN_NONE; }
static PyObject *CMContext_get_font_matrix(CMContext *self, PyObject *Py_UNUSED(i)) {
    cm_matrix_t m; cm_get_font_matrix(self->ctx, &m); return matrix_from_cm(&m); }
static PyObject *CMContext_set_font_options(CMContext *self, PyObject *args) {
    PyObject *o; if (!PyArg_ParseTuple(args, "O!", &CMFontOptionsType, &o)) return NULL;
    cm_set_font_options(self->ctx, ((CMFontOptions *)o)->opt); Py_RETURN_NONE; }
static PyObject *CMContext_get_font_options(CMContext *self, PyObject *Py_UNUSED(i)) {
    cm_font_options_t *o = cm_font_options_create();
    if (!o) { PyErr_SetString(CairoError, "cm_font_options_create failed"); return NULL; }
    cm_get_font_options(self->ctx, o); return wrap_font_options(o); }
static PyObject *CMContext_set_font_face(CMContext *self, PyObject *args) {
    PyObject *ff; if (!PyArg_ParseTuple(args, "O!", &CMFontFaceType, &ff)) return NULL;
    cm_set_font_face(self->ctx, ((CMFontFace *)ff)->face); Py_RETURN_NONE; }
static PyObject *CMContext_get_font_face(CMContext *self, PyObject *Py_UNUSED(i)) {
    cm_font_face_t *ff = cm_get_font_face(self->ctx);
    return wrap_font_face(cm_font_face_reference(ff), 1); }
static PyObject *CMContext_set_scaled_font(CMContext *self, PyObject *args) {
    PyObject *sf; if (!PyArg_ParseTuple(args, "O!", &CMScaledFontType, &sf)) return NULL;
    cm_set_scaled_font(self->ctx, ((CMScaledFont *)sf)->sf); Py_RETURN_NONE; }
static PyObject *CMContext_get_scaled_font(CMContext *self, PyObject *Py_UNUSED(i)) {
    cm_scaled_font_t *sf = cm_get_scaled_font(self->ctx);
    return wrap_scaled_font(cm_scaled_font_reference(sf)); }
static PyObject *CMContext_show_text(CMContext *self, PyObject *args) {
    const char *utf8; if (!PyArg_ParseTuple(args, "s", &utf8)) return NULL;
    cm_show_text(self->ctx, utf8); if (cm_check_ctx(self->ctx) < 0) return NULL; Py_RETURN_NONE; }
static PyObject *CMContext_text_path(CMContext *self, PyObject *args) {
    const char *utf8; if (!PyArg_ParseTuple(args, "s", &utf8)) return NULL;
    cm_text_path(self->ctx, utf8); Py_RETURN_NONE; }
static PyObject *CMContext_text_extents(CMContext *self, PyObject *args) {
    const char *utf8; if (!PyArg_ParseTuple(args, "s", &utf8)) return NULL;
    cm_text_extents_t e; cm_text_extents(self->ctx, utf8, &e);
    return Py_BuildValue("(dddddd)", e.x_bearing, e.y_bearing, e.width, e.height, e.x_advance, e.y_advance); }
static PyObject *CMContext_font_extents(CMContext *self, PyObject *Py_UNUSED(i)) {
    cm_font_extents_t e; cm_font_extents(self->ctx, &e);
    return Py_BuildValue("(ddddd)", e.ascent, e.descent, e.height, e.max_x_advance, e.max_y_advance); }

/* ---- glyph drawing / metrics (cairo_show_glyphs / glyph_path / glyph_extents
 * + show_text_glyphs); glyphs is a sequence of (index, x, y) tuples. ---- */
static PyObject *CMContext_show_glyphs(CMContext *self, PyObject *args) {
    PyObject *seq; if (!PyArg_ParseTuple(args, "O", &seq)) return NULL;
    int n = 0; cm_glyph_t *g = glyphs_as_cm(seq, &n);
    if (!g) { if (PyErr_Occurred()) return NULL; Py_RETURN_NONE; } /* empty run */
    cm_show_glyphs(self->ctx, g, n);
    free(g);
    if (cm_check_ctx(self->ctx) < 0) return NULL;
    Py_RETURN_NONE; }
/* show_text_glyphs(utf8, glyphs, clusters, cluster_flags): the cluster map is
 * accessibility/copy metadata only -- the engine draws the supplied glyph run
 * exactly like show_glyphs (as cairo's image backend does).  We accept clusters
 * as a sequence of (num_bytes, num_glyphs) for signature compatibility and pass
 * them through to the backing (which ignores them for the rendered result). */
static PyObject *CMContext_show_text_glyphs(CMContext *self, PyObject *args) {
    const char *utf8; Py_ssize_t utf8_len;
    PyObject *gseq, *cseq; int cflags = 0;
    if (!PyArg_ParseTuple(args, "s#OO|i", &utf8, &utf8_len, &gseq, &cseq, &cflags))
        return NULL;
    int n = 0; cm_glyph_t *g = glyphs_as_cm(gseq, &n);
    if (!g) { if (PyErr_Occurred()) return NULL; Py_RETURN_NONE; }
    /* Marshal clusters (optional; tolerate None / empty). */
    cm_text_cluster_t *cl = NULL; int ncl = 0;
    if (cseq && cseq != Py_None) {
        PyObject *fast = PySequence_Fast(cseq, "clusters must be a sequence of (num_bytes, num_glyphs)");
        if (!fast) { free(g); return NULL; }
        Py_ssize_t cn = PySequence_Fast_GET_SIZE(fast);
        if (cn > 0) {
            cl = (cm_text_cluster_t *)malloc((size_t)cn * sizeof(cm_text_cluster_t));
            if (!cl) { Py_DECREF(fast); free(g); return PyErr_NoMemory(); }
            for (Py_ssize_t i = 0; i < cn; ++i) {
                PyObject *it = PySequence_Fast_GET_ITEM(fast, i);
                if (!PyArg_ParseTuple(it, "ii", &cl[i].num_bytes, &cl[i].num_glyphs)) {
                    PyErr_Clear();
                    PyErr_Format(PyExc_TypeError,
                        "cluster %zd must be a 2-tuple (num_bytes, num_glyphs)", i);
                    free(cl); Py_DECREF(fast); free(g); return NULL;
                }
            }
            ncl = (int)cn;
        }
        Py_DECREF(fast);
    }
    cm_show_text_glyphs(self->ctx, utf8, (int)utf8_len, g, n, cl, ncl,
                        (cm_text_cluster_flags_t)cflags);
    free(cl); free(g);
    if (cm_check_ctx(self->ctx) < 0) return NULL;
    Py_RETURN_NONE; }
static PyObject *CMContext_glyph_path(CMContext *self, PyObject *args) {
    PyObject *seq; if (!PyArg_ParseTuple(args, "O", &seq)) return NULL;
    int n = 0; cm_glyph_t *g = glyphs_as_cm(seq, &n);
    if (!g) { if (PyErr_Occurred()) return NULL; Py_RETURN_NONE; }
    cm_glyph_path(self->ctx, g, n);
    free(g);
    Py_RETURN_NONE; }
static PyObject *CMContext_glyph_extents(CMContext *self, PyObject *args) {
    PyObject *seq; if (!PyArg_ParseTuple(args, "O", &seq)) return NULL;
    int n = 0; cm_glyph_t *g = glyphs_as_cm(seq, &n);
    cm_text_extents_t e;
    if (!g) {
        if (PyErr_Occurred()) return NULL;
        memset(&e, 0, sizeof(e));            /* empty run -> all-zero extents */
        return text_extents_tuple(&e);
    }
    cm_glyph_extents(self->ctx, g, n, &e);
    free(g);
    return text_extents_tuple(&e); }

/* ---- status ---- */
static PyObject *CMContext_status(CMContext *self, PyObject *Py_UNUSED(i)) {
    return PyLong_FromLong(cm_to_cairo_status(cm_context_status(self->ctx))); }

static PyMethodDef CMContext_methods[] = {
    /* state stack */
    {"save",            (PyCFunction)CMContext_save,            METH_NOARGS,  "save()"},
    {"restore",         (PyCFunction)CMContext_restore,         METH_NOARGS,  "restore()"},
    {"get_target",      (PyCFunction)CMContext_get_target,      METH_NOARGS,  "get_target() -> Surface"},
    {"get_group_target",(PyCFunction)CMContext_get_group_target,METH_NOARGS,  "get_group_target() -> Surface"},
    /* compositing state */
    {"set_operator",    (PyCFunction)CMContext_set_operator,    METH_VARARGS, "set_operator(Operator)"},
    {"get_operator",    (PyCFunction)CMContext_get_operator,    METH_NOARGS,  "get_operator() -> Operator"},
    {"set_antialias",   (PyCFunction)CMContext_set_antialias,   METH_VARARGS, "set_antialias(Antialias)"},
    {"get_antialias",   (PyCFunction)CMContext_get_antialias,   METH_NOARGS,  "get_antialias() -> Antialias"},
    {"set_tolerance",   (PyCFunction)CMContext_set_tolerance,   METH_VARARGS, "set_tolerance(t)"},
    {"get_tolerance",   (PyCFunction)CMContext_get_tolerance,   METH_NOARGS,  "get_tolerance() -> float"},
    {"set_dash",        (PyCFunction)CMContext_set_dash,        METH_VARARGS, "set_dash(dashes[, offset])"},
    {"get_dash",        (PyCFunction)CMContext_get_dash,        METH_NOARGS,  "get_dash() -> (dashes, offset)"},
    {"get_dash_count",  (PyCFunction)CMContext_get_dash_count,  METH_NOARGS,  "get_dash_count() -> int"},
    /* transform */
    {"set_matrix",      (PyCFunction)CMContext_set_matrix,      METH_VARARGS, "set_matrix(Matrix)"},
    {"get_matrix",      (PyCFunction)CMContext_get_matrix,      METH_NOARGS,  "get_matrix() -> Matrix"},
    {"identity_matrix", (PyCFunction)CMContext_identity_matrix, METH_NOARGS,  "identity_matrix()"},
    {"scale",           (PyCFunction)CMContext_scale,           METH_VARARGS, "scale(sx, sy)"},
    {"translate",       (PyCFunction)CMContext_translate,       METH_VARARGS, "translate(tx, ty)"},
    {"rotate",          (PyCFunction)CMContext_rotate,          METH_VARARGS, "rotate(radians)"},
    {"transform",       (PyCFunction)CMContext_transform,       METH_VARARGS, "transform(Matrix)"},
    {"user_to_device",  (PyCFunction)CMContext_user_to_device,  METH_VARARGS, "user_to_device(x, y) -> (x, y)"},
    {"user_to_device_distance", (PyCFunction)CMContext_user_to_device_distance, METH_VARARGS, "user_to_device_distance(dx, dy) -> (dx, dy)"},
    {"device_to_user",  (PyCFunction)CMContext_device_to_user,  METH_VARARGS, "device_to_user(x, y) -> (x, y)"},
    {"device_to_user_distance", (PyCFunction)CMContext_device_to_user_distance, METH_VARARGS, "device_to_user_distance(dx, dy) -> (dx, dy)"},
    /* path */
    {"new_path",        (PyCFunction)CMContext_new_path,        METH_NOARGS,  "new_path()"},
    {"new_sub_path",    (PyCFunction)CMContext_new_sub_path,    METH_NOARGS,  "new_sub_path()"},
    {"move_to",         (PyCFunction)CMContext_move_to,         METH_VARARGS, "move_to(x, y)"},
    {"line_to",         (PyCFunction)CMContext_line_to,         METH_VARARGS, "line_to(x, y)"},
    {"curve_to",        (PyCFunction)CMContext_curve_to,        METH_VARARGS, "curve_to(x1, y1, x2, y2, x3, y3)"},
    {"close_path",      (PyCFunction)CMContext_close_path,      METH_NOARGS,  "close_path()"},
    {"rel_move_to",     (PyCFunction)CMContext_rel_move_to,     METH_VARARGS, "rel_move_to(dx, dy)"},
    {"rel_line_to",     (PyCFunction)CMContext_rel_line_to,     METH_VARARGS, "rel_line_to(dx, dy)"},
    {"rel_curve_to",    (PyCFunction)CMContext_rel_curve_to,    METH_VARARGS, "rel_curve_to(dx1, dy1, dx2, dy2, dx3, dy3)"},
    {"rectangle",       (PyCFunction)CMContext_rectangle,       METH_VARARGS, "rectangle(x, y, w, h)"},
    {"arc",             (PyCFunction)CMContext_arc,             METH_VARARGS, "arc(xc, yc, radius, angle1, angle2)"},
    {"arc_negative",    (PyCFunction)CMContext_arc_negative,    METH_VARARGS, "arc_negative(xc, yc, radius, angle1, angle2)"},
    {"has_current_point",(PyCFunction)CMContext_has_current_point,METH_NOARGS,"has_current_point() -> bool"},
    {"get_current_point",(PyCFunction)CMContext_get_current_point,METH_NOARGS,"get_current_point() -> (x, y)"},
    {"path_extents",    (PyCFunction)CMContext_path_extents,    METH_NOARGS,  "path_extents() -> (x1, y1, x2, y2)"},
    {"copy_path",       (PyCFunction)CMContext_copy_path,       METH_NOARGS,  "copy_path() -> Path (iterable of (type, points))"},
    {"copy_path_flat",  (PyCFunction)CMContext_copy_path_flat,  METH_NOARGS,  "copy_path_flat() -> Path with curves flattened to lines"},
    {"append_path",     (PyCFunction)CMContext_append_path,     METH_VARARGS, "append_path(Path) -- replay a copied path onto the current path"},
    /* source / paint */
    {"set_source_rgba", (PyCFunction)CMContext_set_source_rgba, METH_VARARGS, "set_source_rgba(r, g, b[, a])"},
    {"set_source_rgb",  (PyCFunction)CMContext_set_source_rgb,  METH_VARARGS, "set_source_rgb(r, g, b)"},
    {"set_source",      (PyCFunction)CMContext_set_source,      METH_VARARGS, "set_source(Pattern)"},
    {"set_source_surface",(PyCFunction)CMContext_set_source_surface,METH_VARARGS,"set_source_surface(Surface[, x, y])"},
    {"get_source",      (PyCFunction)CMContext_get_source,      METH_NOARGS,  "get_source() -> Pattern"},
    /* fill / stroke params */
    {"set_fill_rule",   (PyCFunction)CMContext_set_fill_rule,   METH_VARARGS, "set_fill_rule(FillRule)"},
    {"get_fill_rule",   (PyCFunction)CMContext_get_fill_rule,   METH_NOARGS,  "get_fill_rule() -> FillRule"},
    {"set_line_width",  (PyCFunction)CMContext_set_line_width,  METH_VARARGS, "set_line_width(w)"},
    {"get_line_width",  (PyCFunction)CMContext_get_line_width,  METH_NOARGS,  "get_line_width() -> float"},
    {"set_line_join",   (PyCFunction)CMContext_set_line_join,   METH_VARARGS, "set_line_join(LineJoin)"},
    {"get_line_join",   (PyCFunction)CMContext_get_line_join,   METH_NOARGS,  "get_line_join() -> LineJoin"},
    {"set_line_cap",    (PyCFunction)CMContext_set_line_cap,    METH_VARARGS, "set_line_cap(LineCap)"},
    {"get_line_cap",    (PyCFunction)CMContext_get_line_cap,    METH_NOARGS,  "get_line_cap() -> LineCap"},
    {"set_miter_limit", (PyCFunction)CMContext_set_miter_limit, METH_VARARGS, "set_miter_limit(limit)"},
    {"get_miter_limit", (PyCFunction)CMContext_get_miter_limit, METH_NOARGS,  "get_miter_limit() -> float"},
    /* fill / stroke / paint / mask */
    {"fill",            (PyCFunction)CMContext_fill,            METH_NOARGS,  "fill()"},
    {"fill_preserve",   (PyCFunction)CMContext_fill_preserve,   METH_NOARGS,  "fill_preserve()"},
    {"stroke",          (PyCFunction)CMContext_stroke,          METH_NOARGS,  "stroke()"},
    {"stroke_preserve", (PyCFunction)CMContext_stroke_preserve, METH_NOARGS,  "stroke_preserve()"},
    {"paint",           (PyCFunction)CMContext_paint,           METH_NOARGS,  "paint()"},
    {"paint_with_alpha",(PyCFunction)CMContext_paint_with_alpha,METH_VARARGS, "paint_with_alpha(alpha)"},
    {"mask",            (PyCFunction)CMContext_mask,            METH_VARARGS, "mask(Pattern)"},
    {"mask_surface",    (PyCFunction)CMContext_mask_surface,    METH_VARARGS, "mask_surface(Surface[, x, y])"},
    /* clip */
    {"clip",            (PyCFunction)CMContext_clip,            METH_NOARGS,  "clip()"},
    {"clip_preserve",   (PyCFunction)CMContext_clip_preserve,   METH_NOARGS,  "clip_preserve()"},
    {"reset_clip",      (PyCFunction)CMContext_reset_clip,      METH_NOARGS,  "reset_clip()"},
    {"clip_extents",    (PyCFunction)CMContext_clip_extents,    METH_NOARGS,  "clip_extents() -> (x1, y1, x2, y2)"},
    {"in_clip",         (PyCFunction)CMContext_in_clip,         METH_VARARGS, "in_clip(x, y) -> bool"},
    {"copy_clip_rectangle_list",(PyCFunction)CMContext_copy_clip_rectangle_list,METH_NOARGS,"copy_clip_rectangle_list() -> [(x,y,w,h), ...]"},
    /* groups */
    {"push_group",      (PyCFunction)CMContext_push_group,      METH_NOARGS,  "push_group()"},
    {"push_group_with_content",(PyCFunction)CMContext_push_group_with_content,METH_VARARGS,"push_group_with_content(Content)"},
    {"pop_group",       (PyCFunction)CMContext_pop_group,       METH_NOARGS,  "pop_group() -> SurfacePattern"},
    {"pop_group_to_source",(PyCFunction)CMContext_pop_group_to_source,METH_NOARGS,"pop_group_to_source()"},
    /* query / hit tests */
    {"fill_extents",    (PyCFunction)CMContext_fill_extents,    METH_NOARGS,  "fill_extents() -> (x1, y1, x2, y2)"},
    {"stroke_extents",  (PyCFunction)CMContext_stroke_extents,  METH_NOARGS,  "stroke_extents() -> (x1, y1, x2, y2)"},
    {"in_fill",         (PyCFunction)CMContext_in_fill,         METH_VARARGS, "in_fill(x, y) -> bool"},
    {"in_stroke",       (PyCFunction)CMContext_in_stroke,       METH_VARARGS, "in_stroke(x, y) -> bool"},
    /* font / text */
    {"select_font_face",(PyCFunction)CMContext_select_font_face,METH_VARARGS, "select_font_face(family[, slant, weight])"},
    {"set_font_size",   (PyCFunction)CMContext_set_font_size,   METH_VARARGS, "set_font_size(size)"},
    {"set_font_matrix", (PyCFunction)CMContext_set_font_matrix, METH_VARARGS, "set_font_matrix(Matrix)"},
    {"get_font_matrix", (PyCFunction)CMContext_get_font_matrix, METH_NOARGS,  "get_font_matrix() -> Matrix"},
    {"set_font_options",(PyCFunction)CMContext_set_font_options,METH_VARARGS, "set_font_options(FontOptions)"},
    {"get_font_options",(PyCFunction)CMContext_get_font_options,METH_NOARGS,  "get_font_options() -> FontOptions"},
    {"set_font_face",   (PyCFunction)CMContext_set_font_face,   METH_VARARGS, "set_font_face(FontFace)"},
    {"get_font_face",   (PyCFunction)CMContext_get_font_face,   METH_NOARGS,  "get_font_face() -> FontFace"},
    {"set_scaled_font", (PyCFunction)CMContext_set_scaled_font, METH_VARARGS, "set_scaled_font(ScaledFont)"},
    {"get_scaled_font", (PyCFunction)CMContext_get_scaled_font, METH_NOARGS,  "get_scaled_font() -> ScaledFont"},
    {"show_text",       (PyCFunction)CMContext_show_text,       METH_VARARGS, "show_text(text)"},
    {"text_path",       (PyCFunction)CMContext_text_path,       METH_VARARGS, "text_path(text)"},
    {"text_extents",    (PyCFunction)CMContext_text_extents,    METH_VARARGS, "text_extents(text) -> (xb, yb, w, h, xa, ya)"},
    {"font_extents",    (PyCFunction)CMContext_font_extents,    METH_NOARGS,  "font_extents() -> (ascent, descent, height, max_x_advance, max_y_advance)"},
    {"show_glyphs",     (PyCFunction)CMContext_show_glyphs,     METH_VARARGS, "show_glyphs(glyphs) -- glyphs is a sequence of (index, x, y)"},
    {"show_text_glyphs",(PyCFunction)CMContext_show_text_glyphs,METH_VARARGS, "show_text_glyphs(utf8, glyphs, clusters, cluster_flags=0)"},
    {"glyph_path",      (PyCFunction)CMContext_glyph_path,      METH_VARARGS, "glyph_path(glyphs) -- append glyph outlines to the current path"},
    {"glyph_extents",   (PyCFunction)CMContext_glyph_extents,   METH_VARARGS, "glyph_extents(glyphs) -> (xb, yb, w, h, xa, ya)"},
    /* status */
    {"status",          (PyCFunction)CMContext_status,          METH_NOARGS,  "status() -> Status int"},
    {NULL}
};

static PyTypeObject CMContextType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "cairo_metal.Context",
    .tp_basicsize = sizeof(CMContext),
    .tp_flags = Py_TPFLAGS_DEFAULT | Py_TPFLAGS_BASETYPE,
    .tp_doc = "Drawing context (cm_context_t).",
    .tp_new = PyType_GenericNew,
    .tp_init = (initproc)CMContext_init,
    .tp_dealloc = (destructor)CMContext_dealloc,
    .tp_methods = CMContext_methods,
};

/* ===========================================================================
 * Enum namespaces  (pycairo exposes cairo.Operator.OVER etc. AND flat
 * cairo.OPERATOR_OVER constants -- we provide both).
 * =========================================================================== */
typedef struct { const char *name; long value; } cm_enum_member_t;

/* Build an IntEnum subclass via the stdlib `enum` module so members compare and
 * repr like pycairo's (cairo.Operator.OVER == 2). Falls back to a plain
 * attribute namespace if `enum` import fails. */
static PyObject *
make_enum(PyObject *enum_mod, const char *qualname, const cm_enum_member_t *members, int n)
{
    PyObject *kw = PyDict_New();
    if (!kw) return NULL;
    for (int i = 0; i < n; ++i) {
        PyObject *v = PyLong_FromLong(members[i].value);
        if (!v || PyDict_SetItemString(kw, members[i].name, v) != 0) {
            Py_XDECREF(v); Py_DECREF(kw); return NULL;
        }
        Py_DECREF(v);
    }
    PyObject *IntEnum = enum_mod ? PyObject_GetAttrString(enum_mod, "IntEnum") : NULL;
    PyObject *result = NULL;
    if (IntEnum) {
        /* IntEnum(qualname, {members}, module="cairo_metal") */
        PyObject *args = Py_BuildValue("(sN)", qualname, kw);  /* steals kw */
        if (args) {
            PyObject *callkw = Py_BuildValue("{s:s}", "module", "cairo_metal");
            if (callkw) {
                result = PyObject_Call(IntEnum, args, callkw);
                Py_DECREF(callkw);
            }
            Py_DECREF(args);
        }
        Py_DECREF(IntEnum);
    } else {
        Py_DECREF(kw);
    }
    return result;  /* may be NULL -> caller handles */
}

/* Add `enumobj` to module under `name`, and also flat PREFIX_MEMBER ints. */
static int
add_enum_and_flats(PyObject *m, const char *name, PyObject *enumobj,
                   const char *flat_prefix, const cm_enum_member_t *members, int n)
{
    if (enumobj) {
        Py_INCREF(enumobj);
        if (PyModule_AddObject(m, name, enumobj) != 0) { Py_DECREF(enumobj); }
    }
    if (flat_prefix) {
        char buf[96];
        for (int i = 0; i < n; ++i) {
            snprintf(buf, sizeof(buf), "%s%s", flat_prefix, members[i].name);
            if (PyModule_AddIntConstant(m, buf, members[i].value) != 0) return -1;
        }
    }
    return 0;
}

/* ===========================================================================
 * Module-level functions  (pycairo compatibility + manim diagnostics)
 * =========================================================================== */
static PyObject *cm_py_cairo_version(PyObject *m, PyObject *a) {
    (void)m; (void)a; return PyLong_FromLong(cm_version()); }

/* ft_font_face_create(path, index=0) -> FontFace loaded from a font FILE.
 * Backed by cm_ft_font_face_create_for_path.  NOTE: this build has no compiled-in
 * FreeType (CM_ENABLE_FREETYPE is off, the iOS-clean default); the file is loaded
 * via CoreText and its REAL glyphs render through the same path as toy faces.
 * The returned face reports FONT_TYPE_FT and is usable with set_font_face(). */
static PyObject *cm_py_ft_font_face_create(PyObject *m, PyObject *args) {
    (void)m;
    const char *path; int index = 0;
    if (!PyArg_ParseTuple(args, "s|i", &path, &index)) return NULL;
    cm_font_face_t *ff = cm_ft_font_face_create_for_path(path, index);
    if (!ff) {
        if (cm_raise_if_error(cm_last_status()) < 0) return NULL;
        PyErr_Format(CairoError, "cairo_metal: could not load font file '%s'", path);
        return NULL;
    }
    return wrap_font_face(ff, 1);   /* owns the face */ }
static PyObject *cm_py_cairo_version_string(PyObject *m, PyObject *a) {
    (void)m; (void)a; return PyUnicode_FromString(cm_version_string()); }

/* --- manim integration diagnostics (carried over from the original shim) --- */
static PyObject *cm_flush_all(PyObject *m, PyObject *a) {
    (void)m; (void)a;
    for (int i = 0; i < g_reg_n; ++i) cmsurface_sync(g_reg[i]);
    Py_RETURN_NONE; }
static PyObject *cm_metal_device(PyObject *m, PyObject *a) {
    (void)m; (void)a;
    extern const char *cm_metal_device_name(void);
    const char *n = cm_metal_device_name();
    return PyUnicode_FromString(n ? n : ""); }
static PyObject *cm_live_surfaces(PyObject *m, PyObject *a) {
    (void)m; (void)a; return PyLong_FromLong(g_reg_n); }
static PyObject *cm_flush_stats(PyObject *m, PyObject *a) {
    (void)m; (void)a; return Py_BuildValue("(ll)", g_flush_total, g_flush_nonempty); }
static PyObject *cm_gpu_selftest(PyObject *m, PyObject *a) {
    (void)m; (void)a;
    extern const char *cm_metal_device_name(void);
    const char *dev = cm_metal_device_name();
    cm_surface_t *s = cm_image_surface_create_argb32(CM_FORMAT_ARGB32, 16, 16);
    if (!s) return Py_BuildValue("(iss)", 0, dev, cm_status_to_string(cm_last_status()));
    cm_context_t *ctx = cm_context_create(s);
    if (!ctx) { cm_surface_destroy(s);
        return Py_BuildValue("(iss)", 0, dev, "cm_context_create failed"); }
    cm_matrix_t I = {1,0,0,1,0,0}; cm_set_matrix(ctx, &I);
    cm_new_path(ctx); cm_move_to(ctx,0,0); cm_line_to(ctx,16,0);
    cm_line_to(ctx,16,16); cm_line_to(ctx,0,16); cm_close_path(ctx);
    cm_set_source_rgba(ctx, 1.0, 1.0, 1.0, 1.0);
    cm_fill_preserve(ctx);
    cm_surface_flush(s);
    cm_status_t st = cm_context_status(ctx);
    size_t stride = 0;
    unsigned char *px = (unsigned char *)cm_surface_map_argb32(s, &stride);
    int center = -1;
    if (px && stride) { unsigned char *p = px + (size_t)8*stride + (size_t)8*4;
        center = p[0] | p[1] | p[2] | p[3]; }
    char msg[96];
    snprintf(msg, sizeof(msg), "center_px=%d status=%s", center, cm_status_to_string(st));
    cm_context_destroy(ctx); cm_surface_destroy(s);
    return Py_BuildValue("(iss)", (center > 0) ? 1 : 0, dev, msg); }

static PyMethodDef module_methods[] = {
    {"cairo_version",        cm_py_cairo_version,        METH_NOARGS, "cairo version as int"},
    {"cairo_version_string", cm_py_cairo_version_string, METH_NOARGS, "cairo version string"},
    {"ft_font_face_create",  cm_py_ft_font_face_create,  METH_VARARGS,"ft_font_face_create(path, index=0) -> FontFace loaded from a font file"},
    {"_flush_all",           cm_flush_all,               METH_NOARGS, "flush all live create_for_data surfaces (manim per-frame hook)"},
    {"metal_device_name",    cm_metal_device,            METH_NOARGS, "name of the live Metal GPU device (\"\" if unavailable)"},
    {"live_surfaces",        cm_live_surfaces,           METH_NOARGS, "number of live create_for_data surfaces"},
    {"gpu_selftest",         cm_gpu_selftest,            METH_NOARGS, "render+readback a test pattern; returns (ok, device, msg)"},
    {"flush_stats",          cm_flush_stats,             METH_NOARGS, "(total_flushes, nonempty_flushes)"},
    {NULL}
};

/* ===========================================================================
 * Module init
 * =========================================================================== */
static PyModuleDef cairometalmodule = {
    PyModuleDef_HEAD_INIT,
    .m_name = "cairo_metal",
    .m_doc = "Full pycairo-compatible shim over the GPU-backed CairoMetal C API.",
    .m_size = -1,
    .m_methods = module_methods,
};

/* Helper: PyType_Ready + INCREF + add to module under `pyname`. */
static int add_type(PyObject *m, const char *pyname, PyTypeObject *t) {
    if (PyType_Ready(t) < 0) return -1;
    Py_INCREF(t);
    if (PyModule_AddObject(m, pyname, (PyObject *)t) != 0) { Py_DECREF(t); return -1; }
    return 0;
}

PyMODINIT_FUNC
PyInit_cairo_metal(void)
{
    PyObject *m = PyModule_Create(&cairometalmodule);
    if (!m) return NULL;

    /* Exception type: cairo_metal.Error (mirrors cairo.Error). */
    CairoError = PyErr_NewException("cairo_metal.Error", NULL, NULL);
    if (!CairoError) goto fail;
    Py_INCREF(CairoError);
    if (PyModule_AddObject(m, "Error", CairoError) != 0) { Py_DECREF(CairoError); goto fail; }

    /* Types (order matters: bases before subclasses). */
    if (add_type(m, "Matrix",           &CMMatrixType)           < 0) goto fail;
    if (add_type(m, "Surface",          &CMSurfaceType)          < 0) goto fail;
    if (add_type(m, "ImageSurface",     &CMImageSurfaceType)     < 0) goto fail;
    if (add_type(m, "RecordingSurface", &CMRecordingSurfaceType) < 0) goto fail;
    if (add_type(m, "Pattern",          &CMPatternType)          < 0) goto fail;
    if (add_type(m, "SolidPattern",     &CMSolidPatternType)     < 0) goto fail;
    if (add_type(m, "SurfacePattern",   &CMSurfacePatternType)   < 0) goto fail;
    if (add_type(m, "RasterSourcePattern", &CMRasterSourcePatternType) < 0) goto fail;
    if (add_type(m, "Gradient",         &CMGradientType)         < 0) goto fail;
    if (add_type(m, "LinearGradient",   &CMLinearGradientType)   < 0) goto fail;
    if (add_type(m, "RadialGradient",   &CMRadialGradientType)   < 0) goto fail;
    if (add_type(m, "MeshPattern",      &CMMeshPatternType)      < 0) goto fail;
    if (add_type(m, "Region",           &CMRegionType)           < 0) goto fail;
    if (add_type(m, "FontOptions",      &CMFontOptionsType)      < 0) goto fail;
    if (add_type(m, "FontFace",         &CMFontFaceType)         < 0) goto fail;
    if (add_type(m, "ToyFontFace",      &CMToyFontFaceType)      < 0) goto fail;
    if (add_type(m, "ScaledFont",       &CMScaledFontType)       < 0) goto fail;
    if (add_type(m, "Context",          &CMContextType)          < 0) goto fail;
    if (add_type(m, "Path",             &CMPathType)             < 0) goto fail;
    if (add_type(m, "PathIterator",     &CMPathIterType)         < 0) goto fail;

    /* ---- Enums (IntEnum members + flat PREFIX_NAME ints, cairo-exact) ---- */
    PyObject *enum_mod = PyImport_ImportModule("enum");  /* borrowed handling below */

    /* `_mem` is a plain (non-static) local so runtime initializers like
     * cm_to_cairo_status(...) in the Status enum are allowed. */
    #define ENUM(PYNAME, FLATPREFIX, ...) do {                                   \
        const cm_enum_member_t _mem[] = { __VA_ARGS__ };                         \
        int _n = (int)(sizeof(_mem)/sizeof(_mem[0]));                            \
        PyObject *_e = make_enum(enum_mod, PYNAME, _mem, _n);                    \
        if (add_enum_and_flats(m, PYNAME, _e, FLATPREFIX, _mem, _n) < 0)         \
            { Py_XDECREF(_e); Py_XDECREF(enum_mod); goto fail; }                 \
        Py_XDECREF(_e);                                                          \
    } while (0)

    ENUM("Format", "FORMAT_",
        {"INVALID", CM_FORMAT_INVALID}, {"ARGB32", CM_FORMAT_ARGB32},
        {"RGB24", CM_FORMAT_RGB24}, {"A8", CM_FORMAT_A8}, {"A1", CM_FORMAT_A1},
        {"RGB16_565", CM_FORMAT_RGB16_565}, {"RGB30", CM_FORMAT_RGB30});
    ENUM("Content", "CONTENT_",
        {"COLOR", CM_CONTENT_COLOR}, {"ALPHA", CM_CONTENT_ALPHA},
        {"COLOR_ALPHA", CM_CONTENT_COLOR_ALPHA});
    ENUM("Operator", "OPERATOR_",
        {"CLEAR", CM_OPERATOR_CLEAR}, {"SOURCE", CM_OPERATOR_SOURCE},
        {"OVER", CM_OPERATOR_OVER}, {"IN", CM_OPERATOR_IN}, {"OUT", CM_OPERATOR_OUT},
        {"ATOP", CM_OPERATOR_ATOP}, {"DEST", CM_OPERATOR_DEST},
        {"DEST_OVER", CM_OPERATOR_DEST_OVER}, {"DEST_IN", CM_OPERATOR_DEST_IN},
        {"DEST_OUT", CM_OPERATOR_DEST_OUT}, {"DEST_ATOP", CM_OPERATOR_DEST_ATOP},
        {"XOR", CM_OPERATOR_XOR}, {"ADD", CM_OPERATOR_ADD}, {"SATURATE", CM_OPERATOR_SATURATE},
        {"MULTIPLY", CM_OPERATOR_MULTIPLY}, {"SCREEN", CM_OPERATOR_SCREEN},
        {"OVERLAY", CM_OPERATOR_OVERLAY}, {"DARKEN", CM_OPERATOR_DARKEN},
        {"LIGHTEN", CM_OPERATOR_LIGHTEN}, {"COLOR_DODGE", CM_OPERATOR_COLOR_DODGE},
        {"COLOR_BURN", CM_OPERATOR_COLOR_BURN}, {"HARD_LIGHT", CM_OPERATOR_HARD_LIGHT},
        {"SOFT_LIGHT", CM_OPERATOR_SOFT_LIGHT}, {"DIFFERENCE", CM_OPERATOR_DIFFERENCE},
        {"EXCLUSION", CM_OPERATOR_EXCLUSION}, {"HSL_HUE", CM_OPERATOR_HSL_HUE},
        {"HSL_SATURATION", CM_OPERATOR_HSL_SATURATION}, {"HSL_COLOR", CM_OPERATOR_HSL_COLOR},
        {"HSL_LUMINOSITY", CM_OPERATOR_HSL_LUMINOSITY});
    ENUM("Antialias", "ANTIALIAS_",
        {"DEFAULT", CM_ANTIALIAS_DEFAULT}, {"NONE", CM_ANTIALIAS_NONE},
        {"GRAY", CM_ANTIALIAS_GRAY}, {"SUBPIXEL", CM_ANTIALIAS_SUBPIXEL},
        {"FAST", CM_ANTIALIAS_FAST}, {"GOOD", CM_ANTIALIAS_GOOD}, {"BEST", CM_ANTIALIAS_BEST});
    ENUM("FillRule", "FILL_RULE_",
        {"WINDING", CM_FILL_RULE_WINDING}, {"EVEN_ODD", CM_FILL_RULE_EVEN_ODD});
    ENUM("LineCap", "LINE_CAP_",
        {"BUTT", CM_LINE_CAP_BUTT}, {"ROUND", CM_LINE_CAP_ROUND}, {"SQUARE", CM_LINE_CAP_SQUARE});
    ENUM("LineJoin", "LINE_JOIN_",
        {"MITER", CM_LINE_JOIN_MITER}, {"ROUND", CM_LINE_JOIN_ROUND}, {"BEVEL", CM_LINE_JOIN_BEVEL});
    ENUM("Extend", "EXTEND_",
        {"NONE", CM_EXTEND_NONE}, {"REPEAT", CM_EXTEND_REPEAT},
        {"REFLECT", CM_EXTEND_REFLECT}, {"PAD", CM_EXTEND_PAD});
    ENUM("Filter", "FILTER_",
        {"FAST", CM_FILTER_FAST}, {"GOOD", CM_FILTER_GOOD}, {"BEST", CM_FILTER_BEST},
        {"NEAREST", CM_FILTER_NEAREST}, {"BILINEAR", CM_FILTER_BILINEAR},
        {"GAUSSIAN", CM_FILTER_GAUSSIAN});
    ENUM("PatternType", "PATTERN_TYPE_",
        {"SOLID", CM_PATTERN_TYPE_SOLID}, {"SURFACE", CM_PATTERN_TYPE_SURFACE},
        {"LINEAR", CM_PATTERN_TYPE_LINEAR}, {"RADIAL", CM_PATTERN_TYPE_RADIAL},
        {"MESH", CM_PATTERN_TYPE_MESH}, {"RASTER_SOURCE", CM_PATTERN_TYPE_RASTER_SOURCE});
    ENUM("FontSlant", "FONT_SLANT_",
        {"NORMAL", CM_FONT_SLANT_NORMAL}, {"ITALIC", CM_FONT_SLANT_ITALIC},
        {"OBLIQUE", CM_FONT_SLANT_OBLIQUE});
    ENUM("FontWeight", "FONT_WEIGHT_",
        {"NORMAL", CM_FONT_WEIGHT_NORMAL}, {"BOLD", CM_FONT_WEIGHT_BOLD});
    ENUM("FontType", "FONT_TYPE_",
        {"TOY", CM_FONT_TYPE_TOY}, {"FT", CM_FONT_TYPE_FT}, {"USER", CM_FONT_TYPE_USER});
    ENUM("SubpixelOrder", "SUBPIXEL_ORDER_",
        {"DEFAULT", CM_SUBPIXEL_ORDER_DEFAULT}, {"RGB", CM_SUBPIXEL_ORDER_RGB},
        {"BGR", CM_SUBPIXEL_ORDER_BGR}, {"VRGB", CM_SUBPIXEL_ORDER_VRGB},
        {"VBGR", CM_SUBPIXEL_ORDER_VBGR});
    ENUM("HintStyle", "HINT_STYLE_",
        {"DEFAULT", CM_HINT_STYLE_DEFAULT}, {"NONE", CM_HINT_STYLE_NONE},
        {"SLIGHT", CM_HINT_STYLE_SLIGHT}, {"MEDIUM", CM_HINT_STYLE_MEDIUM},
        {"FULL", CM_HINT_STYLE_FULL});
    ENUM("HintMetrics", "HINT_METRICS_",
        {"DEFAULT", CM_HINT_METRICS_DEFAULT}, {"OFF", CM_HINT_METRICS_OFF},
        {"ON", CM_HINT_METRICS_ON});
    ENUM("PathDataType", "PATH_",
        {"MOVE_TO", CM_PATH_MOVE_TO}, {"LINE_TO", CM_PATH_LINE_TO},
        {"CURVE_TO", CM_PATH_CURVE_TO}, {"CLOSE_PATH", CM_PATH_CLOSE_PATH});
    ENUM("RegionOverlap", "REGION_OVERLAP_",
        {"IN", CM_REGION_OVERLAP_IN}, {"OUT", CM_REGION_OVERLAP_OUT},
        {"PART", CM_REGION_OVERLAP_PART});
    ENUM("SurfaceType", "SURFACE_TYPE_",
        {"IMAGE", CM_SURFACE_TYPE_IMAGE}, {"RECORDING", CM_SURFACE_TYPE_RECORDING},
        {"SUBSURFACE", CM_SURFACE_TYPE_SUBSURFACE});
    /* Status: expose the cairo-numbered subset CairoMetal can actually report. */
    ENUM("Status", "STATUS_",
        {"SUCCESS", cm_to_cairo_status(CM_STATUS_SUCCESS)},
        {"NO_MEMORY", cm_to_cairo_status(CM_STATUS_NO_MEMORY)},
        {"INVALID_RESTORE", cm_to_cairo_status(CM_STATUS_INVALID_RESTORE)},
        {"INVALID_POP_GROUP", cm_to_cairo_status(CM_STATUS_INVALID_POP_GROUP)},
        {"NO_CURRENT_POINT", cm_to_cairo_status(CM_STATUS_NO_CURRENT_POINT)},
        {"INVALID_MATRIX", cm_to_cairo_status(CM_STATUS_INVALID_MATRIX)},
        {"INVALID_DASH", cm_to_cairo_status(CM_STATUS_INVALID_DASH)},
        {"CLIP_NOT_REPRESENTABLE", cm_to_cairo_status(CM_STATUS_CLIP_NOT_REPRESENTABLE)},
        {"INVALID_INDEX", cm_to_cairo_status(CM_STATUS_INVALID_INDEX)},
        {"PATTERN_TYPE_MISMATCH", cm_to_cairo_status(CM_STATUS_PATTERN_TYPE_MISMATCH)},
        {"SURFACE_TYPE_MISMATCH", cm_to_cairo_status(CM_STATUS_SURFACE_TYPE_MISMATCH)},
        {"SURFACE_FINISHED", cm_to_cairo_status(CM_STATUS_SURFACE_FINISHED)},
        {"FONT_TYPE_MISMATCH", cm_to_cairo_status(CM_STATUS_FONT_TYPE_MISMATCH)},
        {"INVALID_FORMAT", cm_to_cairo_status(CM_STATUS_INVALID_FORMAT)},
        {"DEVICE_ERROR", cm_to_cairo_status(CM_STATUS_DEVICE_ERROR)});

    #undef ENUM
    Py_XDECREF(enum_mod);

    /* pycairo also exposes version constants at module scope. */
    PyModule_AddStringConstant(m, "version", "1.18.0 (CairoMetal)");
    PyModule_AddIntConstant(m, "version_info", 11800);
    PyModule_AddStringConstant(m, "CAIRO_VERSION_STRING", CM_CAIRO_VERSION_STRING);
    PyModule_AddIntConstant(m, "CAIRO_VERSION", CM_CAIRO_VERSION);

    return m;

fail:
    Py_DECREF(m);
    return NULL;
}
