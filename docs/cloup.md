# cloup — Click extensions (option groups, constraints, aliases)

**Version:** 3.0.5
**Type:** Pure Python
**SPM target:** `Cloup` (auto-pulls `Click`)
**Auto-included by:** Manim (its CLI)
**Total Python modules:** 23

A drop-in superset of `click` that adds the bits Click itself doesn't
ship: option groups in `--help` output, parameter constraints
(`mutually_exclusive`, `all_or_none`, `RequireExactly(2)`), command
aliases, subcommand sections with headers, themed help formatting,
and `Argument`/`Option` types with sensible Pythonic defaults.

Add the `Cloup` SPM target and you also get `Click` automatically.

## Modules

### Top-level

| Module | What it does |
|---|---|
| `cloup.__init__` | Re-exports the public API: `command`, `group`, `option`, `argument`, `option_group`, `Context`, `Command`, `Group`, `Argument`, `Option`, `OptionGroup`, `Section`, `HelpFormatter`, `HelpTheme`, `Style`, `Color`, plus all the `click` types (`BOOL`, `Choice`, `DateTime`, `File`, `Path`, `IntRange`, `FloatRange`, …) |
| `cloup._commands` | `Command`, `Group`, `command`, `group` — cloup's enhanced Click `Command`/`Group` subclasses |
| `cloup._context` | `Context`, `get_current_context`, `pass_context` |
| `cloup._params` | `Argument`, `Option`, `argument`, `option` — drop-in replacements for `click.argument` / `click.option` |
| `cloup._option_groups` | `OptionGroup`, `OptionGroupMixin`, `option_group` decorator |
| `cloup._sections` | `Section`, `SectionMixin` — subcommand grouping in `--help` |
| `cloup._util` | Internal helpers |
| `cloup._version` | `version`, `version_tuple` (setuptools-scm generated) |
| `cloup.styling` | `HelpTheme`, `Style`, `Color` — terminal color theming for help text |
| `cloup.types` | Custom Click parameter types |
| `cloup.typing` | TypeVar / Protocol shims |
| `cloup.warnings` | `CloupWarning` base class + per-feature warning subclasses |

### `cloup.constraints/`

| Module | Provides |
|---|---|
| `constraints._core` | `Constraint`, `And`, `Or`, `RequireAtLeast`, `RequireAtMost`, `RequireExactly`, `RequireBetween`, `AcceptAtMost`, `AcceptBetween`, `accept_none`, `all_or_none`, `mutually_exclusive`, `require_all`, `require_any`, `require_one`, `Operator`, `Rephraser`, `WrapperConstraint`, `ErrorFmt`, `ErrorRephraser`, `HelpRephraser` |
| `constraints._conditional` | `If`, `IsSet`, `Equal`, `AllSet`, `AnySet` — predicates for conditional constraints |
| `constraints._support` | `ConstraintMixin`, `BoundConstraintSpec`, `constrained_params`, `constraint` |
| `constraints.common` | Re-exports common-case constraints |
| `constraints.conditions` | Re-exports the `If`/`IsSet`/`Equal`/`AllSet`/`AnySet` conditions |
| `constraints.exceptions` | `ConstraintViolated`, `UnsatisfiableConstraint` |

### `cloup.formatting/`

| Module | Provides |
|---|---|
| `formatting._formatter` | `HelpFormatter`, `HelpSection` — themed two-column help renderer |
| `formatting._util` | `ensure_is_cloup_formatter`, `unstyled_len` |
| `formatting.sep` | Separator styles (line, blank-line) for help sections |

## iOS-specific patches

None — pure Python, cloup is platform-neutral. The CLI it builds runs
wherever `click` runs, including under iOS-bundled scripts and the
in-app shell.

## Standalone example

```python
import cloup
from cloup import option, option_group
from cloup.constraints import RequireExactly, all_or_none

@cloup.command()
@option_group(
    "Input options",
    option("--from-file",  type=cloup.Path(exists=True)),
    option("--from-url",   type=str),
    option("--from-stdin", is_flag=True),
    constraint=RequireExactly(1),    # exactly one of the three must be set
)
@option_group(
    "Auth (all or none)",
    option("--user"),
    option("--password", hide_input=True),
    constraint=all_or_none,
)
@option("--verbose", is_flag=True)
def fetch(from_file, from_url, from_stdin, user, password, verbose):
    """Fetch data from one of three sources."""
    if from_file:
        ...
    elif from_url:
        ...
    else:
        ...

if __name__ == "__main__":
    fetch()
```

Running `fetch --help` produces a help screen with `Input options:` and
`Auth (all or none):` as distinct, labeled groups instead of one flat
list.

## See also

- [docs/click.md](click.md) — base library; cloup extends it
- [docs/manim.md](manim.md) — primary consumer in the bundle
