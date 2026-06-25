# ~bundler@1.0

A local bundling service. It accepts signed committed items, writes them to the node cache immediately, queues them, and dispatches bundles to Arweave according to operator thresholds.

## When To Use It

- Submit data items to a node-operated bundler.
- Make data optimistically available from local cache before Arweave dispatch completes.
- Operate a bundler queue with size, item-count, and idle-time thresholds.

## Action Keys

| Key | What it does |
|---|---|
| `tx` | Alias for `item`; accepts an item to bundle. |
| `item` | Verify the signed item, cache it locally, meter its byte size, and enqueue it for bundling. |
| `bundler-subject` | Optional request key naming which field contains the item to bundle. |
| `bundler_* config` | Operator settings for workers, max size, max items, idle time, and dispatch timeout. |

## Local Examples

### Create a signed ANS-104 item and upload it

The bundler rejects unsigned bytes. This example asks HyperBEAM to sign and serialize a message with `~ans104@1.0`, then posts those bytes to the local bundler item endpoint.

```text
cat > /tmp/hb-bundler-item.json <<'JSON'
{
  "data": "hello from a signed HyperBEAM bundler item",
  "content-type": "text/plain",
  "app-name": "hb-device-docs"
}
JSON
curl -sS -X POST \
  -H 'content-type: application/json' \
  --data-binary @/tmp/hb-bundler-item.json \
  "http://localhost:8734/~message@1.0/commit&commitment-device=ans104@1.0&type=signed/~ans104@1.0/serialize" \
  -o /tmp/hb-bundler-signed-item.bin
curl -sS -X POST \
  -H 'content-type: application/octet-stream' \
  --data-binary @/tmp/hb-bundler-signed-item.bin \
  "http://localhost:8734/~bundler@1.0/item?codec-device=ans104@1.0"
```

Expected: a successful item submission response with the data-item ID or a configuration/payment response from the local bundler. The important part is that `/tmp/hb-bundler-signed-item.bin` is a real ANS-104 item signed by the node wallet, not arbitrary bytes. The signing step requires `priv-wallet` in the node configuration.

### Confirm unsigned bytes are rejected

```text
printf 'not a signed data item' >/tmp/not-an-item.bin
curl -sS -i -X POST \
  -H 'content-type: application/octet-stream' \
  --data-binary @/tmp/not-an-item.bin \
  "http://localhost:8734/~bundler@1.0/item?codec-device=ans104@1.0"
```

Expected: a `400`-style invalid or unsigned item response. That failure is useful: it proves the bundler is checking commitments before accepting items into a bundle.

### Force a small bundle batch for local testing

```text
cat > /tmp/hb-bundler.flat <<'EOF'
port: 8734
bundler-max-items: 2
bundler-max-bundle-dispatch-delay: 3000
store: rocksdb@1.0
priv-wallet: /path/to/operator-wallet.json
EOF
```

Start a disposable node with that config, run the signed-item upload twice, then check bundler cache paths through `~cache@1.0` or `~query@1.0`. With `bundler-max-items=2`, the second accepted item should make the worker build a bundle transaction rather than waiting for a large production batch.

### Submit an already structured item message

```text
curl -sS -X POST \
  -H 'content-type: application/json' \
  --data-binary '{"data":"structured item body","content-type":"text/plain","commitments":{}}' \
  "http://localhost:8734/~bundler@1.0/tx?bundler-subject=body"
```

Expected: this only succeeds if the posted JSON carries a valid `ans104@1.0` commitment. Use the signed-item example above for a complete path that generates valid bytes.

## Composition

- Use `~ans104@1.0` to sign data items before submission.
- Use `~cache@1.0` to read optimistically cached items by ID.
- Use `~metering@1.0` or `~p4@1.0` when charging for bundled bytes.

## Trust And Operation

The bundler verifies item signatures before queueing. Availability before dispatch is local optimistic cache state; Arweave permanence begins after successful bundle dispatch and confirmation.

## Source

- Root module: `dev_bundler`
- Helper modules: `dev_bundler_cache`, `dev_bundler_recovery`, `dev_bundler_task`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
