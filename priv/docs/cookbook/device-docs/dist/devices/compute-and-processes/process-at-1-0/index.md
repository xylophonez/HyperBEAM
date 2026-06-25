# @PROCESS1.0 Device

This section covers the HyperBEAM `process@1.0` device surface.

Use it to spawn or connect to AO processes, send messages, expose process state over HTTP, and migrate older Legacynet code into the HyperBEAM model.

## Default Path

HyperBEAM is the primary path for new `@PROCESS1.0` work.

The important URL shape is:

```text
http://localhost:8734/<process-id>~process@1.0/<operation>
```

Common operations:

- `push`: send a signed message into a process.
- `compute/<key>`: read the last exposed value for a patched key.
- `now/<key>`: read from the most current process state path.

## Node Selection

For real use, select a current HyperBEAM node from `https://lunar.arweave.net` or another marketplace/listing source. Use the selected node's URL for `--url` and read endpoints. Use that node's advertised address for `HYPERBEAM_NODE_ADDRESS`, then list trusted node addresses in `HYPERBEAM_AUTHORITIES`.

## Section Order

1. Start with the `process@1.0` and processes intro.
2. Use state exposure for fast reads.
3. Build practical patterns on top.
4. Use AO Connect mainnet APIs for JavaScript clients.
5. Keep AOS/Lua basics close by.
6. Use the migration guide for older processes.
7. Keep Legacynet-only material in the final appendix.

## Scope

This section focuses on the English technical core for `process@1.0`: process creation, messages, state exposure, reads, AO Connect, and migration.

Legacynet-specific items are separate from the main flow. They live in [07. Legacynet Appendix](07-legacynet-appendix.md).
