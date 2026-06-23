# HyperBEAM Device Docs

This site is the device and recipe companion to the HyperBEAM docs. The general HyperBEAM and AO-Core story starts in the merged official introduction pages. This home page is a map to the material this corpus adds: local device examples, operator-facing Device Forge docs, and device piping recipes.

## Useful Links

- [What is HyperBEAM?](/introduction/what-is-hyperbeam.md): the official high-level overview.
- [What is AO-Core?](/introduction/what-is-ao-core.md): messages, devices, paths, assignments, and results.
- [AO Devices](/introduction/ao-devices.md): the official device overview, connected to this corpus's device inventory.
- [Reading The Examples](/getting-started/example-style.md): how to read the local `curl` paths used throughout the docs.
- [Device pages](/devices/index.md): the current `edge` core device inventory, grouped by what each device is for.
- [Device Forge](/forge/index.md): how operators build, publish, trust, and load custom devices.
- [Recipes](/recipes/index.md): complete use cases that compose several devices into practical workflows.
- [Reference](/reference/device-inventory.md): inventory, validation notes, and glossary.

## What This Corpus Adds

- Device pages that explain what each core `edge` device does, which keys matter, and how to call it on a local node.
- Recipes that show devices doing useful work together, such as [computing over Arweave JSON with Lua](/recipes/arweave-json-to-lua.md), [querying the local cache](/recipes/query-local-cache.md), and [bundling data locally](/recipes/bundle-data-locally.md).
- Device Forge material for creating, packaging, trusting, and loading custom devices.

The device inventory targets the current `edge` implementation of `permaweb/HyperBEAM` at commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`. The standalone examples assume a local node at `http://localhost:8734`, plus `curl`. Some recipes also show optional `aoconnect` or Node.js snippets inline when wallet-backed requests are involved.

## Path Shape

```text
message -> device key -> result message -> next device key -> next result
```

A device page answers three questions: what the device is for, which keys it exposes, and how to try it locally. A recipe answers a larger question: what useful workflow appears when several devices are piped together.
