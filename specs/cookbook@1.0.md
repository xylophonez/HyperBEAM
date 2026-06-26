# `cookbook@1.0` - docs renderer device

- **Device name:** `cookbook@1.0`
- **Depends-on:** `message@1.0` for normal message dispatch and `hb_docs` for the shared documentation object.
- **Status:** Implemented

## 1. Overview

`cookbook@1.0` is the protocol-native renderer device for HyperBEAM `/docs`
documentation pages. It exposes the documentation object that `hb_docs` builds
for node and device docs routes, while keeping the renderer behind a normal
AO-Core device surface.

The device is intentionally thin. It dispatches renderer keys to `hb_docs`,
which supplies schemas, specs, recipes, component indexes, HTML rendering, JSON
payloads, packaged guide Markdown, and on-weave recipe artifact discovery.

Operators that want the public `/docs` mount SHOULD install `cookbook@1.0` as a
request hook:

```erlang
#{
    <<"on">> => #{
        <<"request">> => #{
            <<"device">> => <<"cookbook@1.0">>,
            <<"path">> => <<"request">>
        }
    }
}
```

The hook MUST pass non-docs requests through unchanged. In particular, `/info`
and `/~meta@1.0/info/...` remain normal device paths.

## 2. Device interface

| Key | Required parameters | Behaviour |
| --- | --- | --- |
| `info` | none | Return documentation for `cookbook@1.0` itself. |
| `request` | hook request | Rewrite `/docs` and `/~device@version/docs` requests to the renderer route. |
| `route` | `docs-kind`, `docs-tail` | Dispatch a rewritten docs route. |
| `index` | none | Render the node-level `/docs` documentation index. |
| `node` | none | Alias of `index`. |
| `device` | optional `for` | Render the `/~device@version/docs` page for the requested device. |
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

The renderer MUST expose the docs shell assets under `/docs/assets/...` when the
request hook is installed.

## 4. Data sources

The shared documentation object MUST include:

1. Device metadata discovered from spec-loaded devices in the node's resolver configuration.
2. Generated schema data from the implementation where available.
3. Parameter documentation inferred from implementation specs where available.
4. Spec bodies loaded by spec transaction ID.
5. On-weave `Device-Recipe` messages whose `recipe-for-device` tag matches the
   spec transaction ID.
6. Packaged introductory and operator guide Markdown from `priv/docs/cookbook`.
7. Implementation traceability for published implementation transactions when available.

Missing coverage MUST be explicit in the structured payload. A missing spec,
recipe set, or implementation record MUST be reported as missing or empty rather
than silently linked to a page that cannot explain itself.

## 5. Conformance

An implementation conforms when:

1. `/~cookbook@1.0/info` returns a `device-info` payload for `cookbook@1.0`.
2. `/~cookbook@1.0/index` and `/~cookbook@1.0/node` render the node docs index.
3. `/~cookbook@1.0/device?for=message@1.0` renders the same device page as
   `/~message@1.0/docs` when the same device is spec-loaded.
4. `/~cookbook@1.0/schema?for=message@1.0`,
   `/~cookbook@1.0/spec?for=message@1.0`, and
   `/~cookbook@1.0/recipes?for=message@1.0` render the corresponding device
   component pages.
5. With the request hook installed, `/docs`, `/docs/schema`, and
   `/~device@version/docs` resolve through `cookbook@1.0/request`.
6. `/info` paths are not intercepted by the docs system.
7. The renderer preserves runnable command formatting from recipe messages and
   does not merge unrelated page prose into a single recipe.
