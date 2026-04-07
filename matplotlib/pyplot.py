"""
matplotlib.pyplot → plotly compatibility layer for OfflinAi.
Translates matplotlib API calls into plotly figures.
Produces interactive HTML charts via fig.show().
100% drop-in: any standard matplotlib code should work unchanged.
"""

import sys as _sys
import numpy as np
import plotly.graph_objects as go

# numpy arrays can't be used in if/and/or — this is handled by
# PythonRuntime which wraps execution to catch and auto-fix these errors.

# ─── Matplotlib-like plotly template ─────────────────────────
# Matches matplotlib 3.x default style as closely as possible.

_MPL_COLORS = ['#1f77b4', '#ff7f0e', '#2ca02c', '#d62728', '#9467bd',
               '#8c564b', '#e377c2', '#7f7f7f', '#bcbd22', '#17becf']
_color_index = [0]

def _next_color():
    c = _MPL_COLORS[_color_index[0] % len(_MPL_COLORS)]
    _color_index[0] += 1
    return c

_MPL_TEMPLATE = go.layout.Template(
    layout=go.Layout(
        paper_bgcolor='white',
        plot_bgcolor='white',
        font=dict(family='Helvetica, Arial, sans-serif', size=12, color='#333333'),
        title=dict(font=dict(size=14, color='#333333'), x=0.5, xanchor='center'),
        xaxis=dict(
            showline=True, linewidth=1, linecolor='#333333', mirror=False,
            showgrid=True, gridwidth=0.5, gridcolor='#d9d9d9', griddash='solid',
            tickfont=dict(size=11), ticks='outside', ticklen=4, tickcolor='#333333',
            zeroline=False,
        ),
        yaxis=dict(
            showline=True, linewidth=1, linecolor='#333333', mirror=False,
            showgrid=True, gridwidth=0.5, gridcolor='#d9d9d9', griddash='solid',
            tickfont=dict(size=11), ticks='outside', ticklen=4, tickcolor='#333333',
            zeroline=False,
        ),
        colorway=_MPL_COLORS,
        legend=dict(
            bgcolor='rgba(255,255,255,0.8)', bordercolor='#cccccc', borderwidth=0.5,
            font=dict(size=11),
        ),
        margin=dict(l=60, r=30, t=50, b=50),
    )
)

# ─── Global State ────────────────────────────────────────────

_current_fig = None
_layout_updates = {}
_annotations = []
_shapes = []
_fig_counter = [0]
_show_hook = None  # Set by PythonRuntime to intercept show()


def _ensure_fig():
    global _current_fig
    if _current_fig is None:
        _current_fig = go.Figure()
        _fig_counter[0] += 1
    return _current_fig


# ─── Safe conversion helpers ─────────────────────────────────

def _to_list(arr):
    """Convert any array-like to a plain Python list, replacing inf/nan with None."""
    if arr is None:
        return None
    if isinstance(arr, (int, float, np.integer, np.floating)):
        v = float(arr)
        return [None if not np.isfinite(v) else v]
    if isinstance(arr, np.ndarray):
        try:
            flat = arr.ravel()
            if flat.dtype.kind == 'f' or flat.dtype.kind == 'c':
                return [None if not np.isfinite(v) else float(v) for v in flat]
            else:
                return [float(v) for v in flat]
        except (TypeError, ValueError):
            return flat.tolist()
    if isinstance(arr, (list, tuple)):
        result = []
        for v in arr:
            try:
                f = float(v)
                result.append(None if not np.isfinite(f) else f)
            except (TypeError, ValueError):
                result.append(v)
        return result
    try:
        return list(arr)
    except TypeError:
        return [arr]


def _to_str_list(arr):
    """Convert to list of strings (for categorical axes)."""
    if arr is None:
        return None
    if isinstance(arr, np.ndarray):
        return [str(v) for v in arr.ravel()]
    if isinstance(arr, (list, tuple)):
        return [str(v) for v in arr]
    return [str(arr)]


def _is_str_array(x):
    """Check if x is a sequence of strings (safe for numpy arrays)."""
    try:
        if isinstance(x, np.ndarray):
            return x.dtype.kind in ('U', 'S', 'O') and len(x) > 0 and isinstance(x.flat[0], str)
        if isinstance(x, (list, tuple)) and len(x) > 0:
            return isinstance(x[0], str)
    except (IndexError, TypeError):
        pass
    return False


def _color_to_str(c):
    """Convert matplotlib color spec to CSS color string."""
    if c is None:
        return None
    if isinstance(c, str):
        _map = {'b': 'blue', 'g': 'green', 'r': 'red', 'c': 'cyan',
                'm': 'magenta', 'y': 'yellow', 'k': 'black', 'w': 'white'}
        return _map.get(c, c)
    if isinstance(c, (tuple, list, np.ndarray)):
        try:
            if len(c) >= 3:
                r, g, b = int(float(c[0])*255), int(float(c[1])*255), int(float(c[2])*255)
                if len(c) >= 4:
                    return f'rgba({r},{g},{b},{float(c[3]):.2f})'
                return f'rgb({r},{g},{b})'
        except (TypeError, ValueError, IndexError):
            pass
    return str(c)


def _parse_fmt(fmt):
    """Parse matplotlib format string like 'b-', 'ro', 'g--'."""
    if not fmt or not isinstance(fmt, str):
        return {}, 'lines'
    color = None
    mode = 'lines'
    marker_sym = None
    line_dash = None

    colors = {'b': 'blue', 'g': 'green', 'r': 'red', 'c': 'cyan',
              'm': 'magenta', 'y': 'yellow', 'k': 'black', 'w': 'white'}
    markers = {'o': 'circle', 's': 'square', '^': 'triangle-up',
               'v': 'triangle-down', 'D': 'diamond', 'x': 'x', '+': 'cross',
               '*': 'star', '.': 'circle', ',': 'circle', 'p': 'pentagon', 'h': 'hexagon'}
    dashes = {'--': 'dash', '-.': 'dashdot', ':': 'dot', '-': 'solid'}

    i = 0
    while i < len(fmt):
        ch = fmt[i]
        if ch in colors and color is None:
            color = colors[ch]; i += 1
        elif ch in markers:
            marker_sym = markers[ch]
            mode = 'markers' if mode == 'lines' else 'lines+markers'
            i += 1
        elif i + 1 < len(fmt) and fmt[i:i+2] in dashes:
            line_dash = dashes[fmt[i:i+2]]; i += 2
        elif ch == '-':
            line_dash = 'solid'; i += 1
        else:
            i += 1

    style = {}
    if color: style['color'] = color
    if marker_sym: style['marker_symbol'] = marker_sym
    if line_dash: style['line_dash'] = line_dash
    return style, mode


def _safe_float(v, default=None):
    if v is None:
        return default
    try:
        f = float(v)
        return f if np.isfinite(f) else default
    except (TypeError, ValueError):
        return default


def _has_len(x):
    """Safe check for __len__ that never triggers numpy truth value error."""
    return hasattr(x, '__len__') and not isinstance(x, str)


# ─── Core Plotting Functions ─────────────────────────────────

def plot(*args, **kwargs):
    """Plot y vs x as lines and/or markers."""
    fig = _ensure_fig()
    label = kwargs.pop('label', None)
    linewidth = _safe_float(kwargs.pop('linewidth', kwargs.pop('lw', None)), 2)
    color = kwargs.pop('color', kwargs.pop('c', None))
    alpha = _safe_float(kwargs.pop('alpha', None))
    linestyle = kwargs.pop('linestyle', kwargs.pop('ls', None))
    marker = kwargs.pop('marker', None)
    markersize = _safe_float(kwargs.pop('markersize', kwargs.pop('ms', None)))
    kwargs.pop('scalex', None); kwargs.pop('scaley', None)
    kwargs.clear()

    if len(args) == 0:
        return []
    elif len(args) == 1:
        y = _to_list(args[0]); x = list(range(len(y))); fmt_style, mode = {}, 'lines'
    elif len(args) == 2:
        if isinstance(args[1], str):
            y = _to_list(args[0]); x = list(range(len(y))); fmt_style, mode = _parse_fmt(args[1])
        else:
            x = _to_list(args[0]); y = _to_list(args[1]); fmt_style, mode = {}, 'lines'
    else:
        x = _to_list(args[0]); y = _to_list(args[1])
        fmt_style, mode = _parse_fmt(args[2]) if isinstance(args[2], str) else ({}, 'lines')

    # Ensure x and y have same length
    if x is not None and y is not None and len(x) != len(y):
        minlen = min(len(x), len(y))
        x, y = x[:minlen], y[:minlen]

    tc = _color_to_str(color) or fmt_style.get('color') or _next_color()
    line_dict = dict(width=linewidth)
    if tc: line_dict['color'] = tc
    dash_map = {'--': 'dash', '-.': 'dashdot', ':': 'dot', '-': 'solid', 'dashed': 'dash', 'dotted': 'dot', 'dashdot': 'dashdot', 'solid': 'solid'}
    if linestyle: line_dict['dash'] = dash_map.get(linestyle, 'solid')
    elif 'line_dash' in fmt_style: line_dict['dash'] = fmt_style['line_dash']

    if marker: mode = 'lines+markers' if 'lines' in mode else 'markers'

    trace = dict(x=x, y=y, mode=mode, line=line_dict)
    if label: trace['name'] = str(label)
    if alpha is not None: trace['opacity'] = alpha
    if marker or fmt_style.get('marker_symbol'):
        mk = dict(size=markersize or 6)
        if tc: mk['color'] = tc
        if fmt_style.get('marker_symbol'): mk['symbol'] = fmt_style['marker_symbol']
        trace['marker'] = mk

    try:
        fig.add_trace(go.Scatter(**trace))
    except Exception as e:
        print(f"[mpl→plotly] plot error: {e}", file=_sys.__stderr__)
    return []


def scatter(x, y, s=None, c=None, marker=None, alpha=None, label=None, cmap=None, vmin=None, vmax=None, edgecolors=None, **kwargs):
    fig = _ensure_fig()
    default_size = 6
    if s is not None:
        mk = dict(size=_safe_float(s, default_size) if not _has_len(s) else _to_list(s))
    else:
        mk = dict(size=default_size)
    if c is not None:
        if isinstance(c, str):
            mk['color'] = _color_to_str(c)
        elif _has_len(c) and not isinstance(c, str):
            mk['color'] = _to_list(c)
            mk['colorscale'] = cmap if isinstance(cmap, str) else 'Viridis'
            mk['showscale'] = True
            if vmin is not None: mk['cmin'] = float(vmin)
            if vmax is not None: mk['cmax'] = float(vmax)
    try:
        fig.add_trace(go.Scatter(x=_to_list(x), y=_to_list(y), mode='markers', marker=mk,
                                 name=label, opacity=_safe_float(alpha)))
    except Exception as e:
        print(f"[mpl→plotly] scatter error: {e}", file=_sys.__stderr__)
    return None


def bar(x, height, width=0.8, bottom=None, color=None, edgecolor=None, label=None, alpha=None, align='center', **kwargs):
    fig = _ensure_fig()
    xl = _to_str_list(x) if _is_str_array(x) else _to_list(x)
    t = dict(x=xl, y=_to_list(height), name=label, opacity=_safe_float(alpha))
    if color is not None: t['marker_color'] = _color_to_str(color)
    if bottom is not None: t['base'] = _to_list(bottom) if _has_len(bottom) else float(bottom)
    try:
        fig.add_trace(go.Bar(**t))
    except Exception as e:
        print(f"[mpl→plotly] bar error: {e}", file=_sys.__stderr__)
    return []


def barh(y, width, height=0.8, left=None, color=None, label=None, **kwargs):
    fig = _ensure_fig()
    try:
        fig.add_trace(go.Bar(y=_to_list(y), x=_to_list(width), orientation='h',
                             name=label, marker_color=_color_to_str(color)))
    except Exception as e:
        print(f"[mpl→plotly] barh error: {e}", file=_sys.__stderr__)
    return []


def hist(x, bins=10, range=None, density=False, cumulative=False, alpha=None, color=None, label=None, histtype='bar', stacked=False, **kwargs):
    fig = _ensure_fig()
    t = dict(x=_to_list(x), nbinsx=int(bins), name=label, opacity=_safe_float(alpha, 0.75))
    if color is not None: t['marker_color'] = _color_to_str(color)
    if density: t['histnorm'] = 'probability density'
    if cumulative: t['cumulative'] = dict(enabled=True)
    try:
        fig.add_trace(go.Histogram(**t))
    except Exception as e:
        print(f"[mpl→plotly] hist error: {e}", file=_sys.__stderr__)
    return [], [], []


def pie(x, labels=None, autopct=None, explode=None, colors=None, startangle=0, shadow=False, **kwargs):
    fig = _ensure_fig()
    t = dict(values=_to_list(x))
    if labels is not None: t['labels'] = _to_str_list(labels)
    if explode is not None: t['pull'] = _to_list(explode)
    if colors is not None: t['marker'] = dict(colors=[_color_to_str(c) for c in colors])
    if autopct: t['textinfo'] = 'percent+label'
    try:
        fig.add_trace(go.Pie(**t))
    except Exception as e:
        print(f"[mpl→plotly] pie error: {e}", file=_sys.__stderr__)


def fill_between(x, y1, y2=0, alpha=0.3, color=None, label=None, where=None, **kwargs):
    fig = _ensure_fig()
    xl, y1l = _to_list(x), _to_list(y1)
    y2l = _to_list(y2) if _has_len(y2) else [float(y2)] * len(xl)
    # Handle 'where' mask
    if where is not None:
        try:
            mask = np.asarray(where, dtype=bool)
            y1a = np.array([float(v) if v is not None else np.nan for v in y1l])
            y2a = np.array([float(v) if v is not None else np.nan for v in y2l])
            y1a[~mask] = np.nan
            y2a[~mask] = np.nan
            y1l = [None if np.isnan(v) else float(v) for v in y1a]
            y2l = [None if np.isnan(v) else float(v) for v in y2a]
        except Exception:
            pass
    fc = _color_to_str(color) if color else 'rgba(68,114,196,0.3)'
    fig.add_trace(go.Scatter(x=xl, y=y1l, mode='lines', line=dict(width=0), showlegend=False))
    fig.add_trace(go.Scatter(x=xl, y=y2l, mode='lines', line=dict(width=0),
                             fill='tonexty', fillcolor=fc, name=label, showlegend=label is not None))


def stem(*args, **kwargs):
    if len(args) == 1:
        y = _to_list(args[0]); x = list(range(len(y)))
    elif len(args) >= 2:
        x, y = _to_list(args[0]), _to_list(args[1])
    else:
        return
    fig = _ensure_fig()
    for xi, yi in zip(x, y):
        if yi is not None:
            fig.add_trace(go.Scatter(x=[xi, xi], y=[0, yi], mode='lines',
                                     line=dict(color='steelblue', width=1), showlegend=False))
    fig.add_trace(go.Scatter(x=x, y=y, mode='markers', marker=dict(color='steelblue', size=6), showlegend=False))


def step(x, y, where='pre', **kwargs):
    fig = _ensure_fig()
    shape = {'pre': 'vh', 'post': 'hv', 'mid': 'hvh'}.get(where, 'vh')
    fig.add_trace(go.Scatter(x=_to_list(x), y=_to_list(y), mode='lines',
                             line=dict(shape=shape, width=kwargs.pop('linewidth', 2)),
                             name=kwargs.pop('label', None)))


def errorbar(x, y, yerr=None, xerr=None, fmt='', label=None, capsize=None, **kwargs):
    fig = _ensure_fig()
    t = dict(x=_to_list(x), y=_to_list(y), name=label, mode='markers')
    if yerr is not None:
        if _has_len(yerr) and not isinstance(yerr, np.ndarray) and len(yerr) == 2:
            t['error_y'] = dict(type='data', symmetric=False, array=_to_list(yerr[1]), arrayminus=_to_list(yerr[0]))
        elif isinstance(yerr, np.ndarray) and yerr.ndim == 2 and yerr.shape[0] == 2:
            t['error_y'] = dict(type='data', symmetric=False, array=_to_list(yerr[1]), arrayminus=_to_list(yerr[0]))
        else:
            t['error_y'] = dict(type='data', array=_to_list(yerr), visible=True)
    if xerr is not None:
        t['error_x'] = dict(type='data', array=_to_list(xerr), visible=True)
    try:
        fig.add_trace(go.Scatter(**t))
    except Exception as e:
        print(f"[mpl→plotly] errorbar error: {e}", file=_sys.__stderr__)


def boxplot(x, labels=None, vert=True, **kwargs):
    fig = _ensure_fig()
    try:
        if _has_len(x) and _has_len(x[0]):
            for i, d in enumerate(x):
                name = labels[i] if labels and i < len(labels) else None
                fig.add_trace(go.Box(y=_to_list(d) if vert else None, x=_to_list(d) if not vert else None, name=name))
        else:
            fig.add_trace(go.Box(y=_to_list(x) if vert else None, x=_to_list(x) if not vert else None))
    except Exception:
        fig.add_trace(go.Box(y=_to_list(x) if vert else None, x=_to_list(x) if not vert else None))


def violinplot(dataset, positions=None, vert=True, **kwargs):
    fig = _ensure_fig()
    try:
        data = dataset if _has_len(dataset) and _has_len(dataset[0]) else [dataset]
    except Exception:
        data = [dataset]
    for i, d in enumerate(data):
        fig.add_trace(go.Violin(y=_to_list(d), name=str(positions[i]) if positions and i < len(positions) else str(i)))


def imshow(data, cmap=None, aspect=None, origin=None, extent=None, vmin=None, vmax=None, interpolation=None, **kwargs):
    fig = _ensure_fig()
    z = data.tolist() if hasattr(data, 'tolist') else data
    t = dict(z=z)
    if cmap and isinstance(cmap, str): t['colorscale'] = cmap
    if vmin is not None: t['zmin'] = float(vmin)
    if vmax is not None: t['zmax'] = float(vmax)
    try:
        fig.add_trace(go.Heatmap(**t))
    except Exception as e:
        print(f"[mpl→plotly] imshow error: {e}", file=_sys.__stderr__)
    if origin == 'lower':
        _layout_updates.setdefault('yaxis', {})['autorange'] = 'reversed'


def contour(*args, levels=None, colors=None, cmap=None, linewidths=None, linestyles=None, _filled=False, **kwargs):
    fig = _ensure_fig()
    X, Y, Z = None, None, None
    if len(args) == 1:
        Z = args[0]
    elif len(args) == 3:
        X, Y, Z = args[0], args[1], args[2]
    elif len(args) == 2:
        Z = args[0]
        if isinstance(args[1], (int, float)):
            levels = args[1]
        elif _has_len(args[1]) and len(args[1]) < 20:
            levels = args[1]
        else:
            Z = args[1]; X = args[0]
    elif len(args) >= 4:
        X, Y, Z = args[0], args[1], args[2]
        if levels is None:
            levels = args[3]

    if Z is None:
        return

    Zarr = np.asarray(Z) if not isinstance(Z, np.ndarray) else Z
    if Zarr.ndim < 2:
        return

    # Extract 1D axes from 2D meshgrid arrays
    if X is not None:
        Xarr = np.asarray(X)
        X = Xarr[0] if Xarr.ndim == 2 else Xarr
    if Y is not None:
        Yarr = np.asarray(Y)
        Y = Yarr[:, 0] if Yarr.ndim == 2 else Yarr

    zl = Zarr.tolist()
    t = dict(z=zl, showscale=_filled)
    if X is not None: t['x'] = _to_list(X)
    if Y is not None: t['y'] = _to_list(Y)

    # Line-only contours (plt.contour) vs filled (plt.contourf)
    if not _filled:
        t['contours_coloring'] = 'lines'
        lw = 2
        if linewidths is not None:
            lw = float(linewidths) if not _has_len(linewidths) else float(linewidths[0])
        t['line'] = dict(width=lw)
        # Single color for all lines
        if colors is not None:
            if isinstance(colors, str):
                t['line']['color'] = _color_to_str(colors)
                t['showscale'] = False
            elif _has_len(colors) and len(colors) > 0:
                t['line']['color'] = _color_to_str(colors[0])
                t['showscale'] = False
        elif cmap is None:
            # Default: single dark blue line (like matplotlib)
            t['line']['color'] = '#1f77b4'
            t['showscale'] = False
        if cmap and isinstance(cmap, str):
            t['colorscale'] = cmap

    else:
        # Filled contour
        if cmap and isinstance(cmap, str):
            t['colorscale'] = cmap

    if levels is not None:
        if isinstance(levels, (int, float, np.integer, np.floating)):
            t['ncontours'] = int(levels)
        elif _has_len(levels):
            lvls = [float(v) for v in levels]
            if len(lvls) == 1:
                t['contours'] = dict(start=lvls[0], end=lvls[0], size=0.001)
            elif len(lvls) > 1:
                t['contours'] = dict(start=min(lvls), end=max(lvls),
                                     size=(max(lvls)-min(lvls))/max(1, len(lvls)-1))
    try:
        fig.add_trace(go.Contour(**t))
    except Exception as e:
        print(f"[mpl→plotly] contour error: {e}", file=_sys.__stderr__)


def contourf(*args, **kwargs):
    kwargs['_filled'] = True
    contour(*args, **kwargs)


def polar(*args, **kwargs):
    fig = _ensure_fig()
    if len(args) >= 2:
        theta, r = _to_list(args[0]), _to_list(args[1])
        theta_deg = [None if t is None else float(t) * 180 / np.pi for t in theta]
        fig.add_trace(go.Scatterpolar(theta=theta_deg, r=r, mode='lines'))
    _layout_updates['polar'] = dict()


def hlines(y, xmin, xmax, colors=None, linestyles=None, label=None, **kwargs):
    ys = [float(y)] if isinstance(y, (int, float, np.integer, np.floating)) else _to_list(y)
    for yv in ys:
        if yv is not None:
            _shapes.append(dict(type='line', x0=float(xmin), x1=float(xmax), y0=yv, y1=yv,
                                line=dict(color=_color_to_str(colors) if colors else 'black')))


def vlines(x, ymin, ymax, colors=None, linestyles=None, label=None, **kwargs):
    xs = [float(x)] if isinstance(x, (int, float, np.integer, np.floating)) else _to_list(x)
    for xv in xs:
        if xv is not None:
            _shapes.append(dict(type='line', y0=float(ymin), y1=float(ymax), x0=xv, x1=xv,
                                line=dict(color=_color_to_str(colors) if colors else 'black')))


# ─── Layout Functions ─────────────────────────────────────────

def title(label, fontsize=None, **kwargs):
    t = dict(text=str(label))
    if fontsize: t['font'] = dict(size=int(fontsize))
    _layout_updates['title'] = t

def suptitle(t, **kwargs):
    title(t, **kwargs)

def xlabel(label, fontsize=None, **kwargs):
    d = _layout_updates.setdefault('xaxis', {})
    d['title'] = dict(text=str(label))
    if fontsize: d['title']['font'] = dict(size=int(fontsize))

def ylabel(label, fontsize=None, **kwargs):
    d = _layout_updates.setdefault('yaxis', {})
    d['title'] = dict(text=str(label))
    if fontsize: d['title']['font'] = dict(size=int(fontsize))

def xlim(*args, **kwargs):
    if len(args) == 2: _layout_updates.setdefault('xaxis', {})['range'] = [float(args[0]), float(args[1])]
    elif len(args) == 1 and _has_len(args[0]): _layout_updates.setdefault('xaxis', {})['range'] = [float(v) for v in args[0]]

def ylim(*args, **kwargs):
    if len(args) == 2: _layout_updates.setdefault('yaxis', {})['range'] = [float(args[0]), float(args[1])]
    elif len(args) == 1 and _has_len(args[0]): _layout_updates.setdefault('yaxis', {})['range'] = [float(v) for v in args[0]]

def grid(visible=True, which='major', axis='both', **kwargs):
    if axis in ('both', 'x'): _layout_updates.setdefault('xaxis', {})['showgrid'] = bool(visible)
    if axis in ('both', 'y'): _layout_updates.setdefault('yaxis', {})['showgrid'] = bool(visible)

def legend(*args, loc=None, fontsize=None, frameon=True, **kwargs):
    _layout_updates['showlegend'] = True

def xticks(ticks=None, labels=None, rotation=None, **kwargs):
    if ticks is not None:
        d = _layout_updates.setdefault('xaxis', {})
        d['tickvals'] = _to_list(ticks)
        if labels is not None: d['ticktext'] = _to_str_list(labels)
        if rotation is not None: d['tickangle'] = -int(rotation)
    return [], []

def yticks(ticks=None, labels=None, rotation=None, **kwargs):
    if ticks is not None:
        d = _layout_updates.setdefault('yaxis', {})
        d['tickvals'] = _to_list(ticks)
        if labels is not None: d['ticktext'] = _to_str_list(labels)
    return [], []

def xscale(scale, **kwargs):
    if scale == 'log': _layout_updates.setdefault('xaxis', {})['type'] = 'log'

def yscale(scale, **kwargs):
    if scale == 'log': _layout_updates.setdefault('yaxis', {})['type'] = 'log'

def axis(arg=None, **kwargs):
    if arg == 'equal': _layout_updates['yaxis'] = dict(scaleanchor='x', scaleratio=1)
    elif arg == 'off': _layout_updates.update(xaxis=dict(visible=False), yaxis=dict(visible=False))
    elif arg == 'tight': pass
    elif arg == 'square': _layout_updates['yaxis'] = dict(scaleanchor='x', scaleratio=1)

def axhline(y=0, color='k', linestyle='-', linewidth=1, label=None, **kwargs):
    dash = {'--': 'dash', '-.': 'dashdot', ':': 'dot'}.get(linestyle, 'solid')
    _shapes.append(dict(type='line', x0=0, x1=1, xref='paper', y0=float(y), y1=float(y),
                        line=dict(color=_color_to_str(color), width=linewidth, dash=dash)))

def axvline(x=0, color='k', linestyle='-', linewidth=1, label=None, **kwargs):
    dash = {'--': 'dash', '-.': 'dashdot', ':': 'dot'}.get(linestyle, 'solid')
    _shapes.append(dict(type='line', y0=0, y1=1, yref='paper', x0=float(x), x1=float(x),
                        line=dict(color=_color_to_str(color), width=linewidth, dash=dash)))

def axhspan(ymin, ymax, alpha=0.3, color=None, **kwargs):
    fc = _color_to_str(color) if color else 'rgba(100,100,200,0.2)'
    _shapes.append(dict(type='rect', x0=0, x1=1, xref='paper', y0=float(ymin), y1=float(ymax),
                        fillcolor=fc, line=dict(width=0), opacity=float(alpha)))

def axvspan(xmin, xmax, alpha=0.3, color=None, **kwargs):
    fc = _color_to_str(color) if color else 'rgba(100,100,200,0.2)'
    _shapes.append(dict(type='rect', y0=0, y1=1, yref='paper', x0=float(xmin), x1=float(xmax),
                        fillcolor=fc, line=dict(width=0), opacity=float(alpha)))

def annotate(text, xy, xytext=None, arrowprops=None, fontsize=None, **kwargs):
    ann = dict(text=str(text), x=float(xy[0]), y=float(xy[1]), showarrow=arrowprops is not None)
    if xytext: ann.update(ax=float(xytext[0]) - float(xy[0]), ay=float(xytext[1]) - float(xy[1]))
    if fontsize: ann['font'] = dict(size=int(fontsize))
    _annotations.append(ann)

def text(x, y, s, fontsize=None, ha=None, va=None, transform=None, **kwargs):
    ann = dict(text=str(s), x=float(x), y=float(y), showarrow=False)
    if fontsize: ann['font'] = dict(size=int(fontsize))
    _annotations.append(ann)

def tight_layout(**kwargs):
    _layout_updates.setdefault('margin', dict(l=50, r=30, t=50, b=50))

def colorbar(mappable=None, ax=None, **kwargs):
    pass

def clim(vmin=None, vmax=None):
    pass

def rcParams_update(d):
    pass

# Module-level rcParams dict (no-op but subscriptable)
rcParams = type('RCParams', (), {
    '__setitem__': lambda s, k, v: None,
    '__getitem__': lambda s, k: None,
    'update': lambda s, d=None, **kw: None,
    'get': lambda s, k, d=None: d,
    '__contains__': lambda s, k: False,
})()


# ─── Figure Management ────────────────────────────────────────

class _SafeFigure:
    """Wraps plotly Figure to catch common errors."""
    def __init__(self, fig):
        object.__setattr__(self, '_fig', fig)
    def __getattr__(self, name):
        return getattr(object.__getattribute__(self, '_fig'), name)
    def __setattr__(self, name, value):
        setattr(object.__getattribute__(self, '_fig'), name, value)
    def update_traces(self, patch=None, **kwargs):
        layout_prefixes = ('xaxis', 'yaxis', 'title', 'legend', 'margin', 'width', 'height',
             'template', 'showlegend', 'paper_bgcolor', 'plot_bgcolor', 'font',
             'coloraxis', 'polar', 'geo', 'mapbox', 'scene')
        layout_keys = [k for k in kwargs if any(k.startswith(p) for p in layout_prefixes)]
        if layout_keys:
            layout_kw = {k: kwargs.pop(k) for k in layout_keys}
            try: object.__getattribute__(self, '_fig').update_layout(**layout_kw)
            except Exception: pass
        if patch or kwargs:
            try: return object.__getattribute__(self, '_fig').update_traces(patch, **kwargs)
            except Exception as e: print(f"[mpl→plotly] update_traces error: {e}", file=_sys.__stderr__)
        return self
    @property
    def data(self):
        return object.__getattribute__(self, '_fig').data
    @data.setter
    def data(self, val):
        object.__getattribute__(self, '_fig').data = val


def figure(num=None, figsize=None, dpi=None, facecolor=None, **kwargs):
    global _current_fig
    _current_fig = go.Figure()
    _fig_counter[0] += 1
    _color_index[0] = 0
    if figsize:
        w, h = figsize
        _layout_updates['width'] = int(w * (dpi or 100))
        _layout_updates['height'] = int(h * (dpi or 100))
    return _SafeFigure(_current_fig)

def subplots(nrows=1, ncols=1, figsize=None, sharex=False, sharey=False, subplot_kw=None, **kwargs):
    sfig = figure(figsize=figsize)
    ax = _Axes(sfig)
    if nrows == 1 and ncols == 1:
        return sfig, ax
    axes = [[_Axes(sfig) for _ in range(ncols)] for _ in range(nrows)]
    if nrows == 1: return sfig, axes[0] if ncols > 1 else axes[0][0]
    if ncols == 1: return sfig, [row[0] for row in axes]
    return sfig, axes

def subplot(*args, **kwargs):
    return _Axes(_ensure_fig())

def axes(*args, **kwargs):
    return _Axes(_ensure_fig())

def gca(**kwargs):
    return _Axes(_ensure_fig())

def gcf():
    return _SafeFigure(_ensure_fig())

def savefig(fname, dpi=None, bbox_inches=None, transparent=False, **kwargs):
    fig = _ensure_fig()
    _apply_layout(fig)
    html_path = str(fname)
    if not html_path.endswith('.html'):
        html_path = html_path.rsplit('.', 1)[0] + '.html'
    fig.write_html(html_path, include_plotlyjs=True)

def show(*args, **kwargs):
    fig = _ensure_fig()
    _apply_layout(fig)
    if _show_hook:
        _show_hook(fig)
    else:
        fig.show()
    _reset()

def close(arg=None):
    if arg is None or arg == 'all':
        _reset()

def get_fignums():
    if _current_fig is not None:
        try:
            if len(_current_fig.data) > 0:
                return [_fig_counter[0]]
        except Exception:
            pass
    return []

def clf():
    _reset()

def cla():
    global _current_fig
    if _current_fig:
        _current_fig.data = []


def _apply_layout(fig):
    updates = dict(_layout_updates)
    updates['template'] = _MPL_TEMPLATE
    if _shapes: updates['shapes'] = list(_shapes)
    if _annotations: updates['annotations'] = list(_annotations)

    # Auto-assign matplotlib colors to traces that don't have explicit colors
    for i, trace in enumerate(fig.data):
        c = _MPL_COLORS[i % len(_MPL_COLORS)]
        if hasattr(trace, 'line') and trace.line is not None:
            if trace.line.color is None:
                trace.line.color = c
        if hasattr(trace, 'marker') and trace.marker is not None:
            if trace.marker.color is None:
                trace.marker.color = c

    try:
        fig.update_layout(**updates)
    except Exception as e:
        print(f"[mpl→plotly] layout error: {e}", file=_sys.__stderr__)
        safe = {k: v for k, v in updates.items() if k in ('template', 'title', 'showlegend', 'margin', 'width', 'height', 'shapes', 'annotations')}
        try: fig.update_layout(**safe)
        except Exception: pass

def _reset():
    global _current_fig
    _current_fig = None
    _layout_updates.clear()
    _annotations.clear()
    _shapes.clear()
    _color_index[0] = 0


# ─── Axes Object (OO interface) ──────────────────────────────

class _Axes:
    """Mimics matplotlib Axes for fig, ax = plt.subplots()."""
    def __init__(self, fig): self._fig = fig

    def plot(self, *a, **kw): return plot(*a, **kw)
    def scatter(self, *a, **kw): return scatter(*a, **kw)
    def bar(self, *a, **kw): return bar(*a, **kw)
    def barh(self, *a, **kw): return barh(*a, **kw)
    def hist(self, *a, **kw): return hist(*a, **kw)
    def pie(self, *a, **kw): return pie(*a, **kw)
    def fill_between(self, *a, **kw): return fill_between(*a, **kw)
    def fill_betweenx(self, *a, **kw): return fill_between(*a, **kw)
    def stem(self, *a, **kw): return stem(*a, **kw)
    def step(self, *a, **kw): return step(*a, **kw)
    def errorbar(self, *a, **kw): return errorbar(*a, **kw)
    def boxplot(self, *a, **kw): return boxplot(*a, **kw)
    def violinplot(self, *a, **kw): return violinplot(*a, **kw)
    def imshow(self, *a, **kw): return imshow(*a, **kw)
    def contour(self, *a, **kw): return contour(*a, **kw)
    def contourf(self, *a, **kw): return contourf(*a, **kw)
    def hlines(self, *a, **kw): return hlines(*a, **kw)
    def vlines(self, *a, **kw): return vlines(*a, **kw)
    def pcolormesh(self, *a, **kw): return imshow(a[-1] if len(a) >= 3 else a[0], **kw)
    def pcolor(self, *a, **kw): return imshow(a[-1] if len(a) >= 3 else a[0], **kw)
    def streamplot(self, *a, **kw): pass  # Not supported, no-op
    def quiver(self, *a, **kw): pass  # Not supported, no-op

    def set_title(self, label, **kw): title(label, **kw)
    def set_xlabel(self, label, **kw): xlabel(label, **kw)
    def set_ylabel(self, label, **kw): ylabel(label, **kw)
    def set_xlim(self, *a, **kw): xlim(*a)
    def set_ylim(self, *a, **kw): ylim(*a)
    def set_xscale(self, s, **kw): xscale(s)
    def set_yscale(self, s, **kw): yscale(s)
    def set_aspect(self, a, **kw): axis('equal') if a == 'equal' else None
    def grid(self, v=True, **kw): grid(v, **kw)
    def legend(self, *a, **kw): legend(*a, **kw)
    def axhline(self, y=0, **kw): axhline(y, **kw)
    def axvline(self, x=0, **kw): axvline(x, **kw)
    def axhspan(self, *a, **kw): axhspan(*a, **kw)
    def axvspan(self, *a, **kw): axvspan(*a, **kw)
    def annotate(self, t, xy, **kw): annotate(t, xy, **kw)
    def text(self, x, y, s, **kw): text(x, y, s, **kw)
    def set_xticks(self, t, labels=None, **kw): xticks(t, labels, **kw)
    def set_yticks(self, t, labels=None, **kw): yticks(t, labels, **kw)
    def set_xticklabels(self, labels, **kw): _layout_updates.setdefault('xaxis', {})['ticktext'] = _to_str_list(labels)
    def set_yticklabels(self, labels, **kw): _layout_updates.setdefault('yaxis', {})['ticktext'] = _to_str_list(labels)
    def tick_params(self, **kw): pass
    def set(self, **kw):
        if 'title' in kw: title(kw['title'])
        if 'xlabel' in kw: xlabel(kw['xlabel'])
        if 'ylabel' in kw: ylabel(kw['ylabel'])
        if 'xlim' in kw: xlim(*kw['xlim'])
        if 'ylim' in kw: ylim(*kw['ylim'])
    def twinx(self): return self
    def twiny(self): return self
    def invert_yaxis(self): _layout_updates.setdefault('yaxis', {})['autorange'] = 'reversed'
    def invert_xaxis(self): _layout_updates.setdefault('xaxis', {})['autorange'] = 'reversed'
    def set_facecolor(self, c): pass
    @property
    def spines(self):
        return type('Spines', (), {'__getitem__': lambda s, k: type('S', (), {'set_visible': lambda s, v: None, 'set_color': lambda s, c: None, 'set_linewidth': lambda s, w: None})()})()
    @property
    def xaxis(self): return type('XAxis', (), {'set_visible': lambda s, v: None, 'set_major_formatter': lambda s, f: None, 'set_minor_formatter': lambda s, f: None})()
    @property
    def yaxis(self): return type('YAxis', (), {'set_visible': lambda s, v: None, 'set_major_formatter': lambda s, f: None, 'set_minor_formatter': lambda s, f: None})()
    @property
    def flat(self): return [self]
    @property
    def transAxes(self): return None
    @property
    def transData(self): return None
