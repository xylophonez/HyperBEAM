# `cookbook@1.0` - docs renderer device

- **Depends-on:** `message@1.0` for normal message dispatch and `hb_docs` for the shared documentation object.
- **Status:** Prototype

## 1. Overview

`cookbook@1.0` is the protocol-native renderer device for the prototype
HyperBEAM `/info` documentation pages. It exposes the same documentation object
that `hb_docs` builds for the node and device info routes, but gives that object
a normal AO-Core device surface so callers can resolve documentation through a
device instead of relying only on a meta-route special case.

The device is intentionally thin. It does not own the long-term information
architecture or replace the full HyperBuddy documentation shell. It dispatches
renderer keys to `hb_docs`, which supplies schemas, specs, recipes, component
indexes, HTML rendering, JSON payloads, and on-weave recipe artifact discovery.

## 2. Device interface

| Key | Required parameters | Behaviour |
| --- | --- | --- |
| `info` | none | Return documentation for `cookbook@1.0` itself. |
| `index` | none | Render the node-level `/info` documentation index. |
| `node` | none | Alias of `index`. |
| `device` | optional `for` | Render the `/~device@version/info` page for the requested device. |
| `schema` | optional `for` | Render the schema page for the requested device. |
| `spec` | optional `for` | Render the spec page for the requested device. |
| `recipes` | optional `for` | Render the recipes page for the requested device. |

If `for` is missing on a device-scoped key, the renderer MUST default to
`message@1.0`. A leading `~` on the `for` value MUST be accepted and stripped
before lookup, so `~message@1.0` and `message@1.0` select the same device.

## 3. Content negotiation

Renderer keys MUST return HTML when the request asks for `text/html`; otherwise
they MUST return the structured documentation payload. The structured payloads
MUST preserve stable links to the node index, device pages, schema pages, spec
pages, recipe pages, and implementation metadata.

The renderer MUST expose the docs shell assets under `/info/assets/...` so the
browser page can load the same CSS and JavaScript runner used by the imported
device-docs cookbook pages.

## 4. Data sources

The shared documentation object MUST include:

1. Static device metadata for the documented devices.
2. Generated schema data from the implementation where available.
3. Parameter documentation for known runnable keys.
4. The inline spec body when `specs/<device>.md` exists.
5. Curated recipe blocks imported from `~/Dev/device-docs`, without treating an
   entire device documentation page as one recipe.
6. Implementation traceability for the source modules backing the documented
   device.

Missing coverage MUST be explicit in the structured payload. A missing spec,
recipe set, or implementation record MUST be reported as missing or empty rather
than silently linked to a page that cannot explain itself.

## 5. Conformance

An implementation conforms when:

1. `/~cookbook@1.0/info` returns a `device-info` payload whose `device-id` is
   `cookbook@1.0`.
2. `/~cookbook@1.0/index` and `/~cookbook@1.0/node` render the node info index.
3. `/~cookbook@1.0/device?for=message@1.0` renders the same device page as
   `/~message@1.0/info`.
4. `/~cookbook@1.0/schema?for=message@1.0`,
   `/~cookbook@1.0/spec?for=message@1.0`, and
   `/~cookbook@1.0/recipes?for=message@1.0` render the corresponding device
   component pages.
5. The renderer preserves runnable command formatting from device-docs and does
   not merge unrelated page prose into a single recipe.
