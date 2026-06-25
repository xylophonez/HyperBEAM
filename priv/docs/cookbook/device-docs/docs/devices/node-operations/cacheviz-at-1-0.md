# ~cacheviz@1.0

A visualization device for the local cache. It can render cache relationships as JSON, DOT, SVG, JavaScript, or an index page.

## When To Use It

- Understand what is in a local cache.
- Debug links and groups created by cache-aware workflows.
- Produce operator-facing visual artifacts.

## Action Keys

| Key | What it does |
|---|---|
| `index` | Serve an index view for cache visualization. |
| `json` | Return graph data as JSON. |
| `dot` | Return Graphviz DOT. |
| `svg` | Return an SVG rendering. |
| `js` | Return browser-side JavaScript used by the viewer. |

## Local Examples

### Render the cache graph UI

```text
curl -sS "http://localhost:8734/~cacheviz@1.0/index" > /tmp/cacheviz.html
```

Open `/tmp/cacheviz.html` or request it from a browser. Expected: an HTML UI that visualizes links in the local cache.

### Get graph JSON for tooling

```bash
curl -sS "http://localhost:8734/~cacheviz@1.0/json"
```

Expected: nodes and edges representing cached messages/links.

### Generate Graphviz DOT or SVG

```text
curl -sS "http://localhost:8734/~cacheviz@1.0/dot" > /tmp/cache.dot
curl -sS "http://localhost:8734/~cacheviz@1.0/svg" > /tmp/cache.svg
```

Expected: DOT/SVG graph output that can be attached to debugging reports after copycat, bundler, or process-state work.

## Composition

- Use after copycat/query/cache recipes to see what was written locally.

## Trust And Operation

This is an operator visualization tool for local state; it does not prove remote availability.

## Source

- Root module: `dev_cacheviz`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
