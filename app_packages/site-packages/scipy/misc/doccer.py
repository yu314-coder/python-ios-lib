import warnings
warnings.warn(
    "scipy.misc.doccer is deprecated and will be removed in 2.0.0",
    DeprecationWarning,
    stacklevel=2
)



# ─── Added: scipy.misc.doccer helpers (deprecated) ──────────────────


def docformat(docstring, docdict=None):
    """Format a docstring with %(name)s placeholders."""
    if docdict and docstring:
        try: return docstring % docdict
        except Exception: return docstring
    return docstring or ''


def extend_notes_in_docstring(cls, notes=''):
    """Append text to the Notes section of cls's docstring."""
    if cls.__doc__:
        cls.__doc__ = cls.__doc__ + '\n' + notes
    return cls


def filldoc(docdict, unindent_params=True):
    """Decorator that fills %(...)s placeholders in a function's
    docstring."""
    def _dec(func):
        if func.__doc__:
            try: func.__doc__ = func.__doc__ % docdict
            except Exception: pass
        return func
    return _dec


def indentcount_lines(lines):
    """Count common indent across non-empty lines."""
    indents = [len(L) - len(L.lstrip()) for L in lines if L.strip()]
    return min(indents) if indents else 0


def inherit_docstring_from(cls):
    """Decorator — inherit docstring from ``cls``."""
    def _dec(method):
        if not method.__doc__:
            for base in cls.__mro__:
                if hasattr(base, method.__name__):
                    base_method = getattr(base, method.__name__)
                    if base_method.__doc__:
                        method.__doc__ = base_method.__doc__
                        break
        return method
    return _dec


def unindent_dict(docdict):
    """Strip common leading whitespace from every value in docdict."""
    return {k: unindent_string(v) for k, v in docdict.items()}


def unindent_string(s):
    """Strip common leading whitespace from a string."""
    if not s: return s
    lines = s.expandtabs().splitlines()
    indent = indentcount_lines(lines[1:]) if len(lines) > 1 else 0
    return '\n'.join([lines[0]] + [L[indent:] for L in lines[1:]])



def replace_notes_in_docstring(cls, notes=''):
    """Replace the Notes section of cls's docstring with ``notes``."""
    if cls.__doc__:
        import re
        cls.__doc__ = re.sub(r'(Notes\s*-----\s*).*?(?=\n\s*\w+\s*-+|\Z)',
                              lambda m: m.group(1) + notes,
                              cls.__doc__, flags=re.DOTALL)
    return cls
