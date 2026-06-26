# Cookbook docs source snapshot

This directory packages the `device-docs` source inputs used by the
`cookbook@1.0` renderer so a HyperBEAM checkout can run the docs pages without
an external docs checkout.

Runtime resolution uses `code:priv_dir(hb)/docs/cookbook/device-docs` by
default. Set `HB_DEVICE_DOCS_ROOT=/path/to/device-docs` only when developing
against a live `device-docs` checkout.

The packaged snapshot contains:

- `docs/`: source Markdown for boilerplate guides plus docs image assets.
- `site/assets/`: the docs UI shell assets served at `/docs/assets/...`.
- `scripts/`: source checks for packaged assets.
- `package.json`: an npm entry point for those checks.

There is intentionally no committed `dist/`, docsify app, copied Markdown tree,
or tracked `node_modules/` content. HyperBEAM renders docs in Erlang, reads
Markdown from `docs/`, and serves assets directly from `site/assets/` and
`docs/assets/`.
