# Small utilities — index

Transitive dependencies bundled because something else needs them. You'd
rarely import any of these directly. Each one now has its own page —
this file is just a table of contents.

## Per-library docs

| Library | Version | What needs it | Doc |
|---|---|---|---|
| **cloup** | 3.0.5 | nicer Click CLIs | [cloup.md](cloup.md) |
| **soupsieve** | 2.8 | CSS-selector engine for BeautifulSoup | [soupsieve.md](soupsieve.md) |
| **rpds-py** | 0.22.3 | persistent data structures for `referencing` / `jsonschema` | [rpds.md](rpds.md) |
| **srt** | 3.5.3 | `.srt` subtitle parsing / writing | [srt.md](srt.md) |
| **pylab** | (ships with matplotlib) | legacy MATLAB-style `pyplot + numpy` namespace | [pylab.md](pylab.md) |
| **torchgen** | 2.1.0 (ships with torch) | PyTorch operator code-generation toolchain (build-time only) | [torchgen.md](torchgen.md) |
| **_distutils_hack** | (ships with setuptools) | import-time shim that registers setuptools' bundled `distutils` | [distutils-hack.md](distutils-hack.md) |
| **pkg_resources** | (ships with setuptools) | legacy package-discovery API (use `importlib.metadata` instead) | [pkg-resources.md](pkg-resources.md) |
| **setuptools** | 82.0.1 | Python package builder; PEP 517 build backend for sdists | [setuptools.md](setuptools.md) |
| **wheel** | 0.46.3 | `.whl` builder + repack / unpack CLI | [wheel.md](wheel.md) |

## Why bundle all of these

They're transitive deps of the libraries we DO want users to interact with:

```
your script
 |- requests          -> certifi, urllib3, idna, charset_normalizer
 |- jsonschema        -> referencing, rpds, attrs
 |- rich              -> markdown_it, mdurl, pygments
 |- click             -> cloup (sometimes)
 |- bs4               -> soupsieve
 |- pip + setuptools  -> wheel, _distutils_hack, pkg_resources
 |- matplotlib        -> pylab
 `- torch             -> torchgen
```

Removing any one of them breaks the corresponding `import`. They add
up to maybe ~15 MB total — small enough that bundling all of them is
the right call.

## See also

- [docs/requests.md](requests.md) / [docs/urllib3.md](urllib3.md) — uses certifi + idna + charset_normalizer
- [docs/jsonschema.md](jsonschema.md) — uses referencing + rpds
- [docs/rich.md](rich.md) — uses markdown_it
- [docs/beautifulsoup.md](beautifulsoup.md) — uses soupsieve
- [docs/click.md](click.md) — sometimes uses cloup
- [docs/pip.md](pip.md) — uses wheel + setuptools
- [docs/minor-libs.md](minor-libs.md) — attrs, packaging, narwhals, referencing (the slightly-bigger transitive deps)
