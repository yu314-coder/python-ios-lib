# typing_extensions — Backported `typing` features

**Version:** 4.15.0
**Type:** Pure Python (single file: `typing_extensions.py`)
**SPM target:** `Typing_extensions`
**Auto-included by:** Pydantic, attrs, referencing, narwhals, FastAPI,
SQLModel, and ~every typed library that wants to support multiple
Python versions
**Total Python modules:** 1 (a ~4300-line single file)

The forward-compat shim for `typing`. Any feature added to stdlib
`typing` in a recent Python version is re-implemented here so libraries
can use it on older runtimes (and import it conditionally with
`if sys.version_info < (3, X): from typing_extensions import ...`).

On iOS we ship Python 3.14, so many of these symbols just delegate to
stdlib `typing`, but downstream code still needs `typing_extensions` for
the names that haven't graduated yet (`TypeIs`, `Doc`, `ReadOnly`, the
new `TypeVar` with `default=`, etc.).

## Module

Single file at `app_packages/site-packages/typing_extensions.py`
(~4317 lines).

### Categories of what it provides

| Category | Symbols |
|---|---|
| Backported / re-exported typing primitives | `Any`, `ClassVar`, `Concatenate`, `Final`, `LiteralString`, `ParamSpec`, `ParamSpecArgs`, `ParamSpecKwargs`, `Self`, `Type`, `TypeAlias`, `TypeAliasType`, `TypeGuard`, `TypeIs`, `TypeVar`, `TypeVarTuple`, `Unpack` |
| ABCs | `Awaitable`, `AsyncIterator`, `AsyncIterable`, `Coroutine`, `AsyncGenerator`, `AsyncContextManager`, `Buffer`, `ChainMap`, `ContextManager`, `Counter`, `Deque`, `DefaultDict`, `OrderedDict` |
| Concrete collections / Protocol | `Protocol`, `runtime_checkable`, `Generic`, `NamedTuple`, `TypedDict`, `Required`, `NotRequired`, `ReadOnly`, `NoExtraItems`, `Sentinel` |
| Decorators / helpers | `final`, `overload`, `override`, `deprecated`, `assert_type`, `assert_never`, `clear_overloads`, `get_overloads`, `get_args`, `get_origin`, `get_type_hints`, `get_protocol_members`, `is_protocol`, `is_typeddict`, `reveal_type` |
| PEP 727 / new (4.x) | `Doc`, `evaluate_forward_ref`, `Format`, `Sentinel`, `get_annotations`, `get_evaluate_type_params`, `NamedTuple` (extended) |
| Newer Python 3.13 / 3.14 backports | `CapsuleType`, `TypeAliasType` with generics, `TypeVar(default=...)`, `ParamSpec(default=...)`, `TypeVarTuple(default=...)`, `Never`, `NoReturn`, `Self`, `Required`, `NotRequired`, `LiteralString`, `Literal` extensions |

If you want the full export list:

```python
import typing_extensions
print(sorted(typing_extensions.__all__))
```

(~180 symbols.)

## iOS-specific patches

None. `typing_extensions` is pure Python with no platform branches —
it only branches on `sys.version_info`. On Python 3.14 (what iOS
ships), almost everything delegates to stdlib `typing`; new symbols
that haven't been upstreamed yet are implemented locally.

## Standalone example

```python
from typing_extensions import (
    TypeVar, Self, override, deprecated, Doc, Annotated, NotRequired, TypedDict,
)

T = TypeVar("T", default=int)   # Python 3.13+ feature, available here

class Stack(list[T]):
    def push(self, value: T) -> Self:
        self.append(value)
        return self            # Self lets the return type stay precise in subclasses

    @override
    def __repr__(self) -> str:
        return f"Stack({list.__repr__(self)})"

class Profile(TypedDict):
    name: str
    bio: NotRequired[str]                                          # optional key
    age: Annotated[int, Doc("Age in years; non-negative")]         # PEP 727 doc string

@deprecated("Use Stack.push instead")
def push_legacy(s, v):
    s.push(v)
```

## See also

- [docs/regex-and-typing.md](regex-and-typing.md) — overview of typing-adjacent libraries in the bundle
- [docs/jsonschema.md](jsonschema.md) — uses `typing_extensions.TypeVar(default=...)` via `referencing`
