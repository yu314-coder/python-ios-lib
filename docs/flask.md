# Flask — web framework

**Version:** 3.x  
**Type:** Pure Python  
**SPM target:** `Flask`  
**Auto-includes:** Werkzeug, Jinja2, Markupsafe, Click  
**Total Python modules:** 24

The "micro" web framework on top of Werkzeug. Routes, sessions, templates, blueprints, request context. Inherits all iOS patches from Werkzeug — works as-is.

## Modules

### Top-level

| Module | What it does |
|---|---|
| `flask.__init__` | Re-exports the public API: `Flask`, `Blueprint`, `request`, `session`, `g`, `current_app`, `url_for`, `redirect`, `flash`, `jsonify`, `render_template`, `send_file`, `send_from_directory`, `abort` |
| `flask.app` | The `Flask` class — application factory, route registration, request dispatch |
| `flask.blueprints` | `Blueprint` — split big apps into reusable, mountable modules |
| `flask.config` | `Config` — environment/file/object-loaded config dict |
| `flask.ctx` | Request context + app context (`current_app`, `g`, `request`) — Werkzeug `LocalProxy`-backed |
| `flask.globals` | The bound proxies (`request`, `session`, `g`, `current_app`) |
| `flask.helpers` | `url_for`, `flash`, `get_flashed_messages`, `send_file`, `send_from_directory`, `stream_with_context`, `make_response`, `redirect`, `abort` |
| `flask.json` | JSON serializer / deserializer (subpackage — see below) |
| `flask.logging` | Default app logger wiring |
| `flask.sessions` | Cookie + secret-key session interface |
| `flask.signals` | Blinker-backed signal hooks (`request_started`, `got_request_exception`, etc.) |
| `flask.templating` | Jinja2 environment + `render_template`, `render_template_string` |
| `flask.testing` | `FlaskClient` test client + `EnvironBuilder` wrapper |
| `flask.views` | Pluggable views: `MethodView`, `View` |
| `flask.wrappers` | `Request`, `Response` — Flask-specific subclasses of Werkzeug's |
| `flask.debughelpers` | Better error messages in debug mode |
| `flask.cli` | The `flask` CLI command, group + command decorators |
| `flask.typing` | Type aliases used by the public API |
| `flask.__main__` | Module entry point — `python -m flask run` |

### `flask.json`

| Submodule | Provides |
|---|---|
| `json.__init__` | `jsonify`, `dumps`, `loads` |
| `json.provider` | `JSONProvider` interface, `DefaultJSONProvider` |
| `json.tag` | `TaggedJSONSerializer` — used by signed sessions |

### `flask.sansio` — I/O-independent core

Used internally; same pattern as Werkzeug's sansio split.

## iOS notes

- All Werkzeug iOS patches transparently apply. `app.run(debug=True)` works thanks to the `multiprocessing.Value` fallback.
- Auto-reload via `debug=True` is silently disabled (Werkzeug's reloader needs `fork()`); file changes don't reload — restart manually.
- Sessions, signed cookies, blueprints, templates, signals, CLI commands all work unchanged.

## Example

```python
from flask import Flask, jsonify, request, render_template_string

app = Flask(__name__)

TEMPLATE = """
<!DOCTYPE html><html><head><meta name="color-scheme" content="light">
<title>Hello</title></head><body>
  <h1>Hello {{ name }}</h1>
  <form method="post"><input name="name"><button>Greet</button></form>
</body></html>
"""

@app.route("/", methods=["GET", "POST"])
def index():
    name = request.form.get("name", "world")
    return render_template_string(TEMPLATE, name=name)

@app.route("/api/data")
def data():
    return jsonify({"value": 42, "ok": True})

# debug=True works on iOS thanks to the werkzeug Value fallback patch.
app.run(host="127.0.0.1", port=5000, debug=True)
```

See [web-stack.md](web-stack.md) for the full iOS framework story.
