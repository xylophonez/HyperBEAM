# AGENTS.md - Cookbook Docs Source

This folder is a packaged snapshot of the `device-docs` source corpus used by
HyperBEAM's `cookbook@1.0` renderer.

## What Lives Here

- `site/assets/`: docs UI shell assets served by HyperBEAM at `/docs/assets/...`.
- `docs/`: Markdown source for reusable boilerplate, process guides, Device
  Forge guides, references, and device-attached recipes.
- `docs/assets/`: images referenced by the source Markdown.
- `scripts/build-docs-site.mjs`: verifies the source-served asset set and
  removes any stale `dist/` tree.

Do not reintroduce a hardcoded `/home/fn/Dev/device-docs` dependency. The
runtime default is this packaged folder via `code:priv_dir(hb)`.

## Dev Server

From the HyperBEAM repo root, use the guarded wrapper (avoids overlapping
`rebar3 shell` instances on port 8734):

```bash
./scripts/dev-server.sh start   # skip if already up
./scripts/dev-server.sh status
./scripts/dev-server.sh restart # after hb_docs / compile changes
```

## Editing Workflow

From this directory:

```bash
npm run docs:build
```

This package intentionally has no npm dependencies and no committed `dist/`.
Do not add docsify build output, copied Markdown, generated sidebars, deploy
artifacts, or tracked `node_modules/` files.

Then run HyperBEAM tests from the repository root:

```bash
rebar3 compile
erl +S 2:2 -pa _build/default/lib/*/ebin -noshell -eval 'case eunit:test(hb_docs, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
```

## Local Live-Checkout Override

Only for local development, a maintainer can point the renderer at another
`device-docs` checkout:

```bash
HB_DEVICE_DOCS_ROOT=/path/to/device-docs rebar3 shell
```

Do not use that override in deploy instructions, tests, or committed service
files. Reviewers should be able to clone HyperBEAM and run the docs without any
external docs checkout.

## Runtime Contract

- HyperBEAM serves docs UI assets from `site/assets/`.
- HyperBEAM serves docs media from `docs/assets/`.
- `hb_docs` reads boilerplate and recipe Markdown source from `docs/`.
- Recipe runner behavior comes from `site/assets/example-runner.js`.
