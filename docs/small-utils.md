# Small utilities — cloup, soupsieve, rpds, srt, pylab, torchgen, _distutils_hack, pkg_resources, setuptools, wheel

Bundled because something else needs them. You'd rarely import any
of these directly. One section per package, with the bare minimum to
explain why it's here and what it does.

---

## cloup (3.0.5)

> Pure Python · `import cloup`

Click extension. Adds option groups, constraints (mutually-exclusive
options, "exactly one of"), aliases, sub-command groups with section
headers, and other niceties on top of `click`. Imported by libraries
that want a more polished CLI than vanilla click provides.

```python
import cloup

@cloup.command()
@cloup.option_group(
    "Auth options",
    cloup.option("--user"),
    cloup.option("--password", hide_input=True),
    constraint=cloup.constraints.all_or_none,
)
def login(user, password):
    ...
```

For most users: stick with stdlib `click`. cloup matters only if a
dependency uses it.

---

## soupsieve (2.8)

> Pure Python · `import soupsieve as sv`

The CSS-selector engine BeautifulSoup uses. When you call
`soup.select("div.foo > a")`, BeautifulSoup forwards to soupsieve.

You'd call directly to test or compile selectors:

```python
import soupsieve as sv
sel = sv.compile("div.foo > a[href*='example']")
print(sel.match(some_tag))
```

Bundled because `bs4` requires it.

---

## rpds-py (0.22.3)

> Native iOS arm64 (Rust via PyO3) · `import rpds`

Python bindings to the Rust `rpds` crate — persistent (immutable)
data structures: HashTrieMap, HashTrieSet, List. Used by `referencing`
(which is used by `jsonschema`) for efficient ref-resolution caches.

You'd call directly only if you need persistent collections in your
own code:

```python
import rpds
m = rpds.HashTrieMap({"a": 1, "b": 2})
m2 = m.insert("c", 3)            # returns a NEW map; m unchanged
print(m, m2)
# HashTrieMap({'a': 1, 'b': 2})  HashTrieMap({'a': 1, 'b': 2, 'c': 3})
```

For most use cases, prefer Python dicts or [pyrsistent](https://pypi.org/project/pyrsistent/)
(more idiomatic API, pure Python). rpds is bundled because
`jsonschema` pulls it in via `referencing`.

---

## srt (3.5.3)

> Pure Python · `import srt`

Parse and generate `.srt` subtitle files. Useful when working with
video output (manim renders, recorded screencasts).

```python
import srt
from datetime import timedelta

# Build subtitles
subs = [
    srt.Subtitle(index=1,
                 start=timedelta(seconds=0),
                 end=timedelta(seconds=2.5),
                 content="Hello, world!"),
    srt.Subtitle(index=2,
                 start=timedelta(seconds=3),
                 end=timedelta(seconds=5),
                 content="On iOS"),
]

# Compose to .srt format
text = srt.compose(subs)
print(text)
# 1
# 00:00:00,000 --> 00:00:02,500
# Hello, world!
#
# 2
# 00:00:03,000 --> 00:00:05,000
# On iOS

# Parse
with open("/path/Documents/clip.srt") as f:
    for sub in srt.parse(f.read()):
        print(f"{sub.start} → {sub.end}: {sub.content}")
```

Pairs naturally with `av` (PyAV) for muxing subtitles into MP4
containers, or with manim renders that have spoken-word audio
tracks.

---

## pylab.py

> Single-module shim · `import pylab`

Re-exports everything from `numpy` + `matplotlib.pyplot` into a
single namespace, mimicking MATLAB's flat `function-name = call`
style. Bundled for ease-of-use compatibility with old code.

```python
import pylab
pylab.plot([1, 2, 3], [4, 5, 6])
pylab.title("hello")
pylab.show()
# (renders via matplotlib's Plotly-backend shim → in-app preview pane)
```

Most modern code uses explicit `import matplotlib.pyplot as plt;
import numpy as np` — `pylab` is the "I'm in a Jupyter notebook
exploring data" shortcut. Either works.

---

## torchgen (subdir of torch)

> Internal · `from torchgen import ...`

PyTorch's code-generation toolchain — used at upstream torch BUILD
time to generate operator dispatch code. NOT used at runtime; ships
in the bundle because it's part of the torch wheel layout. You won't
import it directly unless you're writing a custom op.

If your IDE flags `torchgen` as unused: it's correct. Safe to ignore.

---

## _distutils_hack

> Internal pip / setuptools shim · `import _distutils_hack`

Setuptools' compatibility shim for the (removed in Python 3.12) `distutils`
module. When some legacy code does `import distutils.util`, this hack
intercepts the import and serves setuptools' bundled copy instead.

You should never import this directly. It exists so that older C-extension
sdists that haven't migrated to PEP 517 still install via pip.

---

## pkg_resources (subdir of setuptools)

> Internal · `import pkg_resources` (deprecated; use `importlib.metadata`)

The legacy package-discovery API from setuptools. Many packages still
import it for `pkg_resources.resource_filename(...)` (find a data file
inside a package) or `pkg_resources.get_distribution(name).version`.

Modern equivalent: `importlib.metadata` (stdlib, faster, no setuptools
dependency).

If you see `from pkg_resources import ...` in third-party code, this
is the package providing it.

---

## setuptools (82.0.1)

> Build / packaging tool · `python -m setuptools`

The classic Python package builder. Bundled so `pip install <sdist>`
that depends on setuptools at build time can find it. You won't run
setuptools directly unless you're authoring a Python package.

For most users: nothing to do.

---

## wheel (0.46.3)

> Build / packaging tool · `python -m wheel`

Builds `.whl` files from source. Like setuptools, bundled so pip can
build wheels when needed (sdist → wheel as part of install).

For most users: nothing to do.

---

## Why bundle all of these

They're transitive deps of the libraries we DO want users to interact
with:

```
your script
 ├─ requests          → certifi, urllib3, idna, charset_normalizer
 ├─ jsonschema        → referencing, rpds, attrs
 ├─ rich              → markdown_it, mdurl, pygments
 ├─ click             → cloup (sometimes)
 ├─ bs4               → soupsieve
 ├─ pip + setuptools  → wheel, _distutils_hack, pkg_resources
 ├─ matplotlib        → pylab
 └─ torch             → torchgen
```

Removing any one of them breaks the corresponding `import`. They
add up to maybe ~15 MB total — small enough that bundling all of
them is the right call.

---

## See also

- [docs/requests.md](requests.md) / [docs/urllib3.md](urllib3.md) — uses certifi + idna + charset_normalizer
- [docs/jsonschema.md](jsonschema.md) — uses referencing + rpds
- [docs/rich.md](rich.md) — uses markdown_it
- [docs/beautifulsoup.md](beautifulsoup.md) — uses soupsieve
- [docs/click.md](click.md) — sometimes uses cloup
- [docs/pip.md](pip.md) — uses wheel + setuptools
- [docs/minor-libs.md](minor-libs.md) — attrs, packaging, narwhals,
  referencing (the slightly-bigger transitive deps)
