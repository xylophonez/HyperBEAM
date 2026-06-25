# Using These Docs

This is not a second HyperBEAM quickstart. Use the official introduction pages here for the general model, then use this section to understand how the local device examples are written.

The examples assume:

- A local HyperBEAM node at `http://localhost:8734`.
- `curl` for direct HTTP examples.
- Optional `aoconnect` or Node.js snippets only where wallet-backed requests are useful.

You can point the whole site at another node with the `node` query parameter:

```text
?node=https://mystical.computer
```

When `node` is set, rendered examples that use `http://localhost:8734` are rewritten to that node. Direct `curl` and `GET /...` examples also get a `Run` button that opens the example runner drawer, executes the request from your browser, and shows status, headers, and body. The runner strips presentation codec suffixes from runnable paths, then applies the codec selected in the drawer so the path and response encoding stay separate. Multi-line blocks with simple assignments such as `TXID=...`, `HB=${HB:-http://localhost:8734}`, sequential `curl` calls, and common `grep` filters are run as blocks. The Output tab keeps commands muted and emphasizes results; parseable JSON responses render as a collapsible JSON view, while full request and response detail stays in the Requests tab. Snippets that require command substitution, local files, placeholder IDs, wallet material, or operator state are marked inspect-only.

Recommended order:

1. Read [What is HyperBEAM?](/introduction/what-is-hyperbeam.md) and [What is AO-Core?](/introduction/what-is-ao-core.md) if you need the conceptual base.
2. Read [Reading The Examples](example-style.md) to understand path syntax, typed query values, and shell quoting.
3. Use [Devices](/devices/index.md) when you know which device you need.
4. Use [Recipes](/recipes/index.md) when you want a complete workflow that pipes devices together.
5. Use [Device Forge](/forge/index.md) when you want to create, package, trust, or load your own devices.

For node installation and operator setup, use the current HyperBEAM repository docs for `edge`: `https://github.com/permaweb/HyperBEAM/tree/edge/docs`.
