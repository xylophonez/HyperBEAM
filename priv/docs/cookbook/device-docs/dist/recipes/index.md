# Recipes

Recipes are examples that a reader can run directly against a HyperBEAM node. The approved public set is intentionally small: each runnable block is self-contained, curl-only, and validated against docs-test.

Bad-pattern recipes from the earlier on-weave corpus are quarantined at the docs-test operator config level. A quarantined recipe should not be re-enabled until it follows the [recipe standards](/reference/recipe-standards.md) and passes the validator.

## Approved Runnable Recipes

- [Check docs-test readiness](check-node-readiness.md)
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
- [Trusted custom devices](trusted-custom-device.md)

Inspect workflow pages describe the operation and acceptance criteria but do not publish runnable commands when the action requires wallets, local files, privileged configuration, or seeded node state.
