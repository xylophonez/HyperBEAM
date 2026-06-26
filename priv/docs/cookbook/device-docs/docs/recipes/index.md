# Recipes

Recipes are examples that a reader can run directly against a HyperBEAM node. The approved public set is intentionally small: each runnable block is self-contained, curl-only, and validated against docs-test.

Earlier on-weave recipes that depend on placeholders, local files, or hidden node state are quarantined at the docs-test operator config level. Re-enabled recipes are expected to follow the [recipe standards](/reference/recipe-standards.md) and pass validation.

## Approved Runnable Recipes

- [Read meta node information](read-meta-node-info.md)
- [Build a message and serialize it](message-to-json-pipe.md)
- [Gzip round trip](gzip-round-trip.md)
- [Patch a message key](patch-process-state.md)
- [Run an inline Lua transform](arweave-json-to-lua.md)
- [Inspect an ANS-104 bundling shape](bundle-data-locally.md)
- [Inspect the transaction codec](inspect-transaction-codec.md)
- [Inspect query and match readiness](query-local-cache.md)
- [Build a process-shaped message](create-a-process.md)
- [Inspect a scheduled Lua process shape](scheduled-lua-process.md)
- [Inspect paid access primitives](paid-device-access.md)
- [Inspect relay contract and route policy](relay-fetch-transform.md)

## Inspect Workflows

- [Recorder debug flights](recorder-debug-flight.md)

Inspect workflow pages describe the operation and acceptance criteria while omitting runnable commands for actions that require wallets, local files, privileged configuration, or seeded node state.
