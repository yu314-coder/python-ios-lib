/*
 * cm_state.c  --  CairoMetal graphics-state stack + non-GPU state accessors
 * ============================================================================
 *
 * Owns save/restore (deep-copy push/pop of the COMPOSITE state with source-
 * pattern + clip + font retain/copy), every trivial get/set accessor not tied
 * to the GPU (operator / antialias / tolerance / dash + the getters for
 * fill_rule / line_width / line_join / line_cap / miter_limit), dash
 * validation, and the cm_gstate node lifecycle.  The CURRENT PATH is
 * deliberately OUTSIDE the gstate (cairo does not save/restore the path).
 * Pure C.
 *
 * Where "the current gstate" lives: cm_internal.h folds the live graphics
 * state directly into struct cm_context (ctm, source, fill_rule, line_width,
 * line_join, line_cap, miter_limit, op, antialias, tolerance, dash[*], clip,
 * font_*).  cm_save/cm_restore deep-copy that live block onto / off a stack of
 * cm_gstate snapshot nodes.  The public SETTERS for fill_rule / line_width /
 * line_join / line_cap / miter_limit keep their bodies in cairo_metal.m and
 * simply write those live-gstate fields; this file owns the matching GETTERS
 * plus the operator / antialias / tolerance / dash state, so no public symbol
 * is defined twice across the two translation units.
 *
 * Ownership rules enforced here (must match the sibling modules):
 *   - a non-solid source holds ONE reference on its cm_pattern_t
 *     (cm_pattern_reference / cm_pattern_destroy, cm_pattern.c);
 *   - the clip is a refcounted snapshot (cm_clip_retain / cm_clip_release,
 *     cm_clip.m);
 *   - the font face is refcounted (cm_font_face_reference / _destroy) and the
 *     font options are an OWNED copy (cm_font_options_copy / _destroy),
 *     cm_font.c;
 *   - the dash array is an OWNED malloc'd copy.
 * Every save() takes a reference / copy of each of these; every restore()
 * transfers the snapshot's ownership back to the live state after releasing the
 * live state's own references, so the refcounts stay perfectly balanced and a
 * save without a matching restore is reclaimed by cm_state_free().
 * ============================================================================
 */

#include "cm_internal.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

/* ==========================================================================
 * Owned-copy helpers
 * ========================================================================== */

/* Duplicate the owned dash array (NULL-safe; NULL for an empty pattern). */
static double *cm_dash_dup(const double *src, int n)
{
    if (!src || n <= 0) return NULL;
    double *d = (double *)malloc((size_t)n * sizeof(double));
    if (!d) return NULL;
    memcpy(d, src, (size_t)n * sizeof(double));
    return d;
}

/* ==========================================================================
 * gstate node lifecycle (INTERNAL; cm_internal.h "MODULE: cm_state.c")
 * ========================================================================== */

/* Initialise the LIVE graphics state to the cairo defaults.
 *
 * cm_context_create() sets these same defaults inline today, so this hook is
 * not on the create path; it is the single authoritative description of the
 * default gstate and is safe + idempotent to call on a freshly calloc'd
 * context.  It touches ONLY the live-gstate value fields -- never the path,
 * surface, target, frame, group stack, or any retained reference -- so it can
 * never leak or double-free an owned object. */
void cm_state_init(cm_context_t *ctx)
{
    if (!ctx) return;

    cm_matrix_identity(&ctx->ctm);          /* CTM = identity                  */

    /* cairo default source: opaque black (0,0,0,1).  No re-swap (see the
     * public header's PIXEL FORMAT CONTRACT); the GPU premultiplies at cover. */
    ctx->source.kind    = CM_PAINT_SOLID;
    ctx->source.solid.r = 0.0f;
    ctx->source.solid.g = 0.0f;
    ctx->source.solid.b = 0.0f;
    ctx->source.solid.a = 1.0f;
    ctx->source.pattern = NULL;

    ctx->fill_rule      = CM_FILL_RULE_WINDING;   /* cairo default             */
    ctx->line_width     = 2.0;                    /* cairo default             */
    ctx->line_join      = CM_LINE_JOIN_MITER;     /* cairo default             */
    ctx->line_cap       = CM_LINE_CAP_BUTT;       /* cairo default             */
    ctx->miter_limit    = 10.0;                   /* cairo default             */

    ctx->op             = CM_OPERATOR_OVER;       /* cairo default             */
    ctx->antialias      = CM_ANTIALIAS_DEFAULT;
    ctx->tolerance      = 0.1;                    /* cairo default             */
    ctx->dash           = NULL;
    ctx->dash_count     = 0;
    ctx->dash_offset    = 0.0;
    ctx->global_alpha   = 1.0;

    ctx->clip           = NULL;                   /* unclipped                 */
}

void cm_state_free(cm_context_t *ctx)
{
    if (!ctx) return;

    /* Pop + free every saved gstate node, releasing each node's retained refs
     * (a save() that never got a matching restore() is reclaimed here). */
    cm_gstate *g = ctx->stack;
    while (g) {
        cm_gstate *next = g->next;
        if (g->source.kind != CM_PAINT_SOLID && g->source.pattern)
            cm_pattern_destroy(g->source.pattern);
        free(g->dash);
        if (g->clip)         cm_clip_release(g->clip);
        if (g->font_face)    cm_font_face_destroy(g->font_face);
        if (g->font_options) cm_font_options_destroy(g->font_options);
        free(g);
        g = next;
    }
    ctx->stack = NULL;

    /* Release the LIVE clip + owned dash + group stack. */
    if (ctx->clip) { cm_clip_release(ctx->clip); ctx->clip = NULL; }
    free(ctx->dash); ctx->dash = NULL; ctx->dash_count = 0;

    cm_group *gr = ctx->groups;
    while (gr) {
        cm_group *next = gr->next;
        if (gr->target) cm_surface_destroy(gr->target);
        free(gr);
        gr = next;
    }
    ctx->groups = NULL;
    ctx->group_target = NULL;

    /* Live font state. */
    if (ctx->font_face)    { cm_font_face_destroy(ctx->font_face);       ctx->font_face = NULL; }
    if (ctx->font_options) { cm_font_options_destroy(ctx->font_options); ctx->font_options = NULL; }
    if (ctx->scaled_font)  { cm_scaled_font_destroy(ctx->scaled_font);   ctx->scaled_font = NULL; }
}

/* Free a single snapshot node, releasing every reference/copy it holds.  Used
 * to unwind a partially-built node when a push fails mid-way so the push is
 * ATOMIC (either the whole snapshot is taken or none of it is). */
static void cm_gstate_free_node(cm_gstate *g)
{
    if (!g) return;
    if (g->source.kind != CM_PAINT_SOLID && g->source.pattern)
        cm_pattern_destroy(g->source.pattern);
    free(g->dash);
    if (g->clip)         cm_clip_release(g->clip);
    if (g->font_face)    cm_font_face_destroy(g->font_face);
    if (g->font_options) cm_font_options_destroy(g->font_options);
    free(g);
}

cm_status_t cm_state_push(cm_context_t *ctx)
{
    if (!ctx) return CM_STATUS_NO_MEMORY;

    cm_gstate *g = (cm_gstate *)calloc(1, sizeof(*g));
    if (!g) return CM_STATUS_NO_MEMORY;

    /* Plain value fields. */
    g->ctm          = ctx->ctm;
    g->fill_rule    = ctx->fill_rule;
    g->line_width   = ctx->line_width;
    g->line_join    = ctx->line_join;
    g->line_cap     = ctx->line_cap;
    g->miter_limit  = ctx->miter_limit;
    g->op           = ctx->op;
    g->antialias    = ctx->antialias;
    g->tolerance    = ctx->tolerance;
    g->dash_offset  = ctx->dash_offset;
    g->global_alpha = ctx->global_alpha;
    g->font_matrix  = ctx->font_matrix;

    /* Source: copy the struct, then take a reference if it is a pattern. */
    g->source = ctx->source;
    if (g->source.kind != CM_PAINT_SOLID && g->source.pattern)
        cm_pattern_reference(g->source.pattern);

    /* Owned dash copy.  If the live state HAS a dash but the copy fails, abort
     * the whole push -- committing a node with dash==NULL but dash_count>0 would
     * later restore a context whose dash array and count disagree. */
    g->dash_count = ctx->dash_count;
    if (ctx->dash && ctx->dash_count > 0) {
        g->dash = cm_dash_dup(ctx->dash, ctx->dash_count);
        if (!g->dash) { cm_gstate_free_node(g); return CM_STATUS_NO_MEMORY; }
    } else {
        g->dash       = NULL;
        g->dash_count = 0;
    }

    /* Refcounted clip snapshot + retained/copied font state. */
    g->clip         = ctx->clip        ? cm_clip_retain(ctx->clip)            : NULL;
    g->font_face    = ctx->font_face   ? cm_font_face_reference(ctx->font_face): NULL;
    g->font_options = ctx->font_options? cm_font_options_copy(ctx->font_options): NULL;

    /* Push onto the stack (top == most recent save). */
    g->next    = ctx->stack;
    ctx->stack = g;
    return CM_STATUS_SUCCESS;
}

cm_status_t cm_state_pop(cm_context_t *ctx)
{
    if (!ctx) return CM_STATUS_NO_MEMORY;
    cm_gstate *g = ctx->stack;
    if (!g) return CM_STATUS_INVALID_RESTORE;   /* restore without save        */

    /* Release the LIVE state's owned refs before overwriting them with the
     * snapshot's (whose ownership then transfers wholesale into the context). */
    if (ctx->source.kind != CM_PAINT_SOLID && ctx->source.pattern)
        cm_pattern_destroy(ctx->source.pattern);
    free(ctx->dash);
    if (ctx->clip)         cm_clip_release(ctx->clip);
    if (ctx->font_face)    cm_font_face_destroy(ctx->font_face);
    if (ctx->font_options) cm_font_options_destroy(ctx->font_options);

    /* Restore every saved field; owned objects move (no extra ref/copy). */
    ctx->ctm          = g->ctm;
    ctx->source       = g->source;     /* pattern ownership transfers           */
    ctx->fill_rule    = g->fill_rule;
    ctx->line_width   = g->line_width;
    ctx->line_join    = g->line_join;
    ctx->line_cap     = g->line_cap;
    ctx->miter_limit  = g->miter_limit;
    ctx->op           = g->op;
    ctx->antialias    = g->antialias;
    ctx->tolerance    = g->tolerance;
    ctx->dash         = g->dash;       /* dash array ownership transfers         */
    ctx->dash_count   = g->dash_count;
    ctx->dash_offset  = g->dash_offset;
    ctx->global_alpha = g->global_alpha;
    ctx->clip         = g->clip;       /* clip snapshot ownership transfers      */
    ctx->font_face    = g->font_face;  /* font face ownership transfers          */
    ctx->font_matrix  = g->font_matrix;
    ctx->font_options = g->font_options;/* font options ownership transfers      */

    /* CTM / font state changed -> any cached scaled font is stale.  (The path's
     * device cache is NOT keyed on the saved CTM here; cairo does not save the
     * path, and the next fill/stroke re-flattens against the restored CTM
     * because the recorded verbs are unchanged.  We mark the scaled font dirty
     * so cm_text re-resolves it against the restored font matrix + CTM.) */
    ctx->scaled_font_dirty = true;

    ctx->stack = g->next;
    free(g);    /* the node's owned refs were TRANSFERRED, not released         */
    return CM_STATUS_SUCCESS;
}

/* ==========================================================================
 * Dash validation
 * --------------------------------------------------------------------------
 * cairo_set_dash rules (cairo-exact):
 *   - num_dashes == 0          -> OK, disables dashing (no array required);
 *   - any dash value negative  -> CAIRO_STATUS_INVALID_DASH;
 *   - any dash value non-finite-> invalid (NaN/inf cannot describe a length);
 *   - all dash values zero     -> CAIRO_STATUS_INVALID_DASH (zero total).
 * ========================================================================== */
cm_status_t cm_dash_validate(const double *dashes, int n)
{
    if (n <= 0) return CM_STATUS_SUCCESS;        /* empty disables dashing      */
    if (!dashes) return CM_STATUS_INVALID_DASH;  /* count>0 but no array         */

    double sum = 0.0;
    for (int i = 0; i < n; ++i) {
        double v = dashes[i];
        if (!isfinite(v) || v < 0.0) return CM_STATUS_INVALID_DASH;
        sum += v;
    }
    if (sum <= 0.0) return CM_STATUS_INVALID_DASH;   /* all-zero pattern         */
    return CM_STATUS_SUCCESS;
}

/* ==========================================================================
 * Public: save / restore
 * ========================================================================== */
void cm_save(cm_context_t *ctx)
{
    if (!ctx) return;
    cm_status_t st = cm_state_push(ctx);
    if (st != CM_STATUS_SUCCESS && ctx->status == CM_STATUS_SUCCESS)
        ctx->status = st;
}

void cm_restore(cm_context_t *ctx)
{
    if (!ctx) return;
    cm_status_t st = cm_state_pop(ctx);
    if (st != CM_STATUS_SUCCESS && ctx->status == CM_STATUS_SUCCESS)
        ctx->status = st;            /* underflow -> CM_STATUS_INVALID_RESTORE   */
}

/* ==========================================================================
 * Public: compositing state
 * ========================================================================== */
void cm_set_operator(cm_context_t *ctx, cm_operator_t op)
{
    if (ctx) ctx->op = op;
}
cm_operator_t cm_get_operator(cm_context_t *ctx)
{
    return ctx ? ctx->op : CM_OPERATOR_OVER;
}

void cm_set_antialias(cm_context_t *ctx, cm_antialias_t aa)
{
    if (ctx) ctx->antialias = aa;
}
cm_antialias_t cm_get_antialias(cm_context_t *ctx)
{
    return ctx ? ctx->antialias : CM_ANTIALIAS_DEFAULT;
}

void cm_set_tolerance(cm_context_t *ctx, double tolerance)
{
    /* Ignore non-positive / non-finite tolerances (keep the prior value); the
     * flatten + stroke paths read ctx->tolerance directly and require a finite
     * positive number (they fall back to CM_ARC_TOLERANCE otherwise). */
    if (ctx && isfinite(tolerance) && tolerance > 0.0)
        ctx->tolerance = tolerance;
}
double cm_get_tolerance(cm_context_t *ctx)
{
    return ctx ? ctx->tolerance : 0.1;
}

void cm_set_dash(cm_context_t *ctx, const double *dashes, int num_dashes,
                 double offset)
{
    if (!ctx) return;

    /* Validate first; on INVALID_DASH leave the existing dash UNCHANGED and
     * flag the context (cairo sets the error and does not alter the dash). */
    cm_status_t st = cm_dash_validate(dashes, num_dashes);
    if (st != CM_STATUS_SUCCESS) {
        if (ctx->status == CM_STATUS_SUCCESS) ctx->status = st;
        return;
    }

    /* Replace the owned dash.  num_dashes==0 clears it (dashing disabled);
     * offset is recorded either way (cairo keeps the offset for an empty set). */
    free(ctx->dash);
    ctx->dash        = NULL;
    ctx->dash_count  = 0;
    ctx->dash_offset = offset;

    if (num_dashes > 0) {
        ctx->dash = cm_dash_dup(dashes, num_dashes);
        if (!ctx->dash) {
            if (ctx->status == CM_STATUS_SUCCESS) ctx->status = CM_STATUS_NO_MEMORY;
            return;                  /* leaves a consistent "no dash" state      */
        }
        ctx->dash_count = num_dashes;
    }
}

int cm_get_dash_count(cm_context_t *ctx)
{
    return ctx ? ctx->dash_count : 0;
}

void cm_get_dash(cm_context_t *ctx, double *dashes, double *offset)
{
    if (!ctx) return;
    /* cairo writes the dash array only when there are dashes, and always writes
     * the offset.  The caller is expected to size `dashes` to get_dash_count(). */
    if (dashes && ctx->dash && ctx->dash_count > 0)
        memcpy(dashes, ctx->dash, (size_t)ctx->dash_count * sizeof(double));
    if (offset) *offset = ctx->dash_offset;
}

/* ==========================================================================
 * Public: state GETTERS (the matching setters live in cairo_metal.m, which
 * writes the same live-gstate fields these read)
 * ========================================================================== */
cm_fill_rule_t cm_get_fill_rule(cm_context_t *ctx)
{
    return ctx ? ctx->fill_rule : CM_FILL_RULE_WINDING;
}
double cm_get_line_width(cm_context_t *ctx)
{
    return ctx ? ctx->line_width : 2.0;
}
cm_line_join_t cm_get_line_join(cm_context_t *ctx)
{
    return ctx ? ctx->line_join : CM_LINE_JOIN_MITER;
}
cm_line_cap_t cm_get_line_cap(cm_context_t *ctx)
{
    return ctx ? ctx->line_cap : CM_LINE_CAP_BUTT;
}
double cm_get_miter_limit(cm_context_t *ctx)
{
    return ctx ? ctx->miter_limit : 10.0;
}
