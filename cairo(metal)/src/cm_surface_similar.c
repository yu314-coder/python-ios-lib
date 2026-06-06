/*
 * cm_surface_similar.c  --  create_similar / similar_image / for_rectangle
 * ============================================================================
 *
 * Thin pure-C allocators over cm_surface.m's format-general create + the
 * subsurface/parent wiring, keeping cm_surface.m focused on GPU allocation.
 * This translation unit owns three public entry points:
 *
 *   cm_surface_create_similar(other, content, w, h)
 *       Maps the cairo CONTENT bit-flags to a concrete pixel format
 *       (COLOR -> RGB24, ALPHA -> A8, COLOR_ALPHA -> ARGB32) via the format
 *       table, then forwards to the real GPU allocator.  `other` only selects
 *       the device family; every surface here shares the one process device, so
 *       a compatible surface is just an image surface of the resolved format.
 *
 *   cm_surface_create_similar_image(other, format, w, h)
 *       Same delegation, but the caller already named the concrete format.
 *
 *   cm_surface_create_for_rectangle(target, x, y, w, h)
 *       Builds a SUBSURFACE (kind == CM_SURFACE_TYPE_SUBSURFACE): a lightweight
 *       view that OWNS NO IOSurface/MTLTexture of its own.  It records the
 *       parent (so the device can fetch the parent's colour/MSAA/stencil
 *       textures) and an absolute sub-rect (x,y,w,h) in the parent's pixel
 *       space, and mirrors the parent's device offset so drawing lands at the
 *       sub-origin.  cm_frame_begin (cm_device.m) is the place that applies that
 *       offset + a scissor to the parent's render pass; this file only wires the
 *       data.
 *
 * DELEGATION, not duplication: create_similar(_image) call straight into
 * cm_image_surface_create (cm_surface.m), which validates the format/size,
 * allocates the IOSurface + MSAA + stencil attachments, and sets the
 * thread-local creation status (cm_last_status).  We therefore do NOT re-set the
 * status on those paths -- the allocator already did, exactly as the other thin
 * wrappers in cm_surface.m (e.g. cm_image_surface_create_for_data) rely on.
 *
 * OWNERSHIP / LIFETIME (cross-module seam -- see notes at end of file):
 *   cm_surface (cm_internal.h) has no refcount and the public API exposes no
 *   cm_surface_reference(); ownership in this codebase is by transfer (cf.
 *   cm_group.m handing an offscreen surface into a SurfacePattern).  A
 *   subsurface therefore holds a BORROWED pointer to its parent: the parent must
 *   outlive every subsurface taken on it (this is also true of cairo's own
 *   subsurface, which keeps the parent alive via a reference -- here the caller
 *   is responsible for ordering destroys).  cm_surface_destroy (cm_surface.m)
 *   already tears a subsurface down safely: every GPU handle (iosurface /
 *   color_tex / msaa_color_tex / stencil_tex / cpu_backing / record) is NULL on
 *   a calloc'd subsurface, so destroy releases nothing it does not own and never
 *   touches ->parent.
 * ============================================================================
 */

#include "cm_internal.h"

#include <math.h>
#include <stdlib.h>

/* --------------------------------------------------------------------------
 * cm_surface_create_similar -- CONTENT -> concrete format, then delegate.
 *
 * cairo_surface_create_similar(other, content, w, h): a surface usable with
 * `other`, with the given content.  `other` chooses the device; we have one
 * process device shared by every surface, so "compatible" reduces to an image
 * surface of the format that realises `content`:
 *     CM_CONTENT_COLOR       -> CM_FORMAT_RGB24   (opaque)
 *     CM_CONTENT_ALPHA       -> CM_FORMAT_A8      (coverage only)
 *     CM_CONTENT_COLOR_ALPHA -> CM_FORMAT_ARGB32  (premultiplied BGRA)
 * cm_format_for_content (cm_surface_format.c) is the single source of that map.
 * -------------------------------------------------------------------------- */
cm_surface_t *cm_surface_create_similar(cm_surface_t *other, cm_content_t content,
                                        int width, int height)
{
    /* cairo requires a valid `other`; with no error-surface object to return we
     * mirror the rest of this file / cm_surface.m (map_to_image, for_rectangle)
     * and fail with a type mismatch on a NULL base. */
    if (!other) {
        cm_set_last_status(CM_STATUS_SURFACE_TYPE_MISMATCH);
        return NULL;
    }

    cm_format_t fmt = cm_format_for_content(content);

    /* Delegate: cm_image_surface_create validates fmt + (w,h), allocates the
     * GPU backing, and sets cm_last_status.  Do not duplicate that status here. */
    return cm_image_surface_create(fmt, width, height);
}

/* --------------------------------------------------------------------------
 * cm_surface_create_similar_image -- caller-named format, then delegate.
 *
 * cairo_surface_create_similar_image(other, format, w, h): always an IMAGE
 * surface (never device-specific), of an explicit cairo_format_t.  Identical
 * delegation to the format-general allocator; `other` only documents the device
 * family, which is process-global here.
 * -------------------------------------------------------------------------- */
cm_surface_t *cm_surface_create_similar_image(cm_surface_t *other, cm_format_t format,
                                              int width, int height)
{
    if (!other) {
        cm_set_last_status(CM_STATUS_SURFACE_TYPE_MISMATCH);
        return NULL;
    }
    /* Delegate (validates format/size + sets cm_last_status). */
    return cm_image_surface_create(format, width, height);
}

/* --------------------------------------------------------------------------
 * cm_surface_create_for_rectangle -- a SUBSURFACE view onto `target`.
 *
 * cairo_surface_create_for_rectangle(target, x, y, w, h): a surface that draws
 * into the (x,y,w,h) window of `target`'s storage.  We model it as a view that
 * owns no GPU memory:
 *   - kind        = CM_SURFACE_TYPE_SUBSURFACE  (the discriminator; there is no
 *                   separate is_subsurface flag -- `kind` IS the flag)
 *   - parent      = the IOSurface-backed base whose textures the device binds
 *   - sub_rect    = the ABSOLUTE (root-pixel-space) window to scissor to
 *   - dev_off_{x,y} = the same (x,y) origin, kept as the one documented place
 *                   cm_frame_begin reads the draw offset from
 *   - format/stride/dev = inherited from the base (same pixels, same layout)
 *
 * Nested subsurfaces are FLATTENED: if `target` is itself a subsurface we walk
 * to its real IOSurface-backed root and compose the offsets, so `parent` always
 * points at a surface that actually has textures and `sub_rect` is expressed in
 * that root's pixel space.  This matches how cairo collapses a subsurface of a
 * subsurface, and it is what the device scissor needs (it can only scissor the
 * real backing, not a virtual view).
 * -------------------------------------------------------------------------- */
cm_surface_t *cm_surface_create_for_rectangle(cm_surface_t *target,
                                              double x, double y,
                                              double width, double height)
{
    if (!target) {
        cm_set_last_status(CM_STATUS_SURFACE_TYPE_MISMATCH);
        return NULL;
    }
    /* A finished surface has released its backing; cairo flags ops on it as
     * SURFACE_FINISHED.  (Status code 12 in the public mapping.) */
    if (target->finished) {
        cm_set_last_status(CM_STATUS_SURFACE_FINISHED);
        return NULL;
    }
    /* cairo permits a subsurface whose rect extends past the parent, but the
     * geometry must be finite and non-negative in extent; reject the rest so the
     * device scissor never sees NaN / negative spans. */
    if (!isfinite(x) || !isfinite(y) ||
        !isfinite(width) || !isfinite(height) ||
        width < 0.0 || height < 0.0) {
        cm_set_last_status(CM_STATUS_INVALID_FORMAT);
        return NULL;
    }

    /* Flatten nested subsurfaces: resolve the real IOSurface-backed root and add
     * up the sub-origins so the new view references textures that exist and a
     * rect in root pixel space.  (A non-subsurface root contributes a 0,0
     * offset.)  parent->parent chains are finite -- each create_for_rectangle
     * links to an already-resolved root, so this is at most one hop, but the
     * loop is robust to any chain depth. */
    cm_surface_t *base = target;
    double base_off_x = 0.0, base_off_y = 0.0;
    while (base->kind == CM_SURFACE_TYPE_SUBSURFACE && base->parent) {
        base_off_x += base->sub_rect.x;
        base_off_y += base->sub_rect.y;
        base = base->parent;
    }

    double abs_x = base_off_x + x;
    double abs_y = base_off_y + y;

    cm_surface_t *s = (cm_surface_t *)calloc(1, sizeof(*s));
    if (!s) {
        cm_set_last_status(CM_STATUS_NO_MEMORY);
        return NULL;
    }

    /* A subsurface shares the root's device + GPU resources; it owns no
     * IOSurface, MSAA, or stencil texture of its own (all NULL from calloc, so
     * cm_surface_destroy releases nothing here and leaves ->parent untouched).
     * The borrowed `parent` points at the real backing; `sub_rect` is the
     * absolute scissor window in that backing's pixel space. */
    s->dev          = base->dev;
    s->kind         = CM_SURFACE_TYPE_SUBSURFACE;
    s->format       = base->format;          /* same pixels => same format       */
    s->width        = (int)width;
    s->height       = (int)height;
    s->stride       = base->stride;          /* row layout of the shared backing */
    s->parent       = base;                  /* BORROWED: base must outlive `s`  */

    s->sub_rect.x      = abs_x;
    s->sub_rect.y      = abs_y;
    s->sub_rect.width  = width;
    s->sub_rect.height = height;

    /* Single documented draw-offset for cm_frame_begin: where user (0,0) on this
     * subsurface lands in the root backing.  Kept in lock-step with sub_rect.x/y
     * so the device has one place to read it (get/set_device_offset also see a
     * sane value for introspection). */
    s->dev_off_x    = abs_x;
    s->dev_off_y    = abs_y;

    s->status       = CM_STATUS_SUCCESS;
    s->refcount     = 1;                     /* creator holds the first reference */

    cm_set_last_status(CM_STATUS_SUCCESS);
    return s;
}

/*
 * ============================================================================
 * CROSS-MODULE SEAMS the Build phase must reconcile
 * ----------------------------------------------------------------------------
 * 1. cm_frame_begin (cm_device.m) currently fetches msaa/resolve/stencil from
 *    the surface's OWN accessors and returns SURFACE_TYPE_MISMATCH when they are
 *    NULL -- which is always true for a SUBSURFACE.  To make drawing into a
 *    subsurface work it must, when surface->kind == CM_SURFACE_TYPE_SUBSURFACE,
 *    bind surface->parent's textures and then apply the sub-origin
 *    (surface->dev_off_x/y, == surface->sub_rect.x/y) plus a scissor rect of
 *    (sub_rect.x, sub_rect.y, width, height) clamped to the parent's bounds.
 *    All the data it needs is already on the struct; only that branch is
 *    missing.  This file deliberately does NOT touch cm_device.m.
 *
 * 2. Lifetime: there is no refcount on cm_surface and no public
 *    cm_surface_reference(), so the subsurface's ->parent is a BORROWED pointer
 *    -- the parent must be destroyed AFTER its subsurfaces.  If the Build phase
 *    wants cairo's "subsurface keeps the parent alive" guarantee, it needs to
 *    add a refcount to cm_surface + retain ->parent here and release it in
 *    cm_surface_destroy (both in cm_surface.m / cm_internal.h, which are out of
 *    scope for this module).  Today's behaviour is consistent with the rest of
 *    the tree (ownership by transfer, e.g. cm_group.m).
 * ============================================================================
 */
