# aiohttp — async HTTP client/server 3.14.1 (iOS)

Bundled in **C-extension mode** — the real Cython accelerators are cross-compiled
for iOS arm64, not the pure-Python fallback: `_http_parser` (llhttp), `_http_writer`,
plus C-extension builds of its dep stack (`multidict._multidict`, `yarl._quoting_c`,
`frozenlist._frozenlist`, `propcache`, `aiosignal`, `aiohappyeyeballs`). Built via
`aiohttp_ios/build_aiohttp.sh`.

## What works

- **Client**: `aiohttp.ClientSession` — GET/POST/streaming, JSON, timeouts,
  cookies, connection pooling, WebSocket client (`ws_connect`)
- **Server**: `aiohttp.web` — routes, middlewares, WebSockets, served on
  localhost the same way flask/dash/streamlit run in-app (bind `127.0.0.1`,
  open the preview pane)
- asyncio event loop on iOS works normally (single process)

## Gaps

| Feature | Status | Workaround |
|---|---|---|
| `aiodns` resolver | Not bundled (needs `pycares` C ext) | Default threaded resolver is used automatically |
| Brotli response decoding | `brotli`/`brotlicffi` not bundled | gzip/deflate work; request `Accept-Encoding: gzip` |
| Client certs from the iOS keychain | Python's ssl uses certifi, not the system store | Pass `ssl=ssl_context` with your own CA/cert files |
| Multi-process server workers | iOS forbids `fork()` | Single event-loop process (plenty for on-device serving) |

## Build notes (recipe: `aiohttp_ios/`)

- PEP 517 project with no `setup.py` → built with `pip wheel --no-build-isolation`
- One C++ Cython extension needs Python headers baked into `CXX`
  (`-I$PY_HDRS`) — plain CC/CFLAGS isn't enough

## See also
- [requests.md](requests.md) / [urllib3.md](urllib3.md) — the sync stack
- [web-stack.md](web-stack.md) — running servers on-device
