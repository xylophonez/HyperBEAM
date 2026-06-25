# Bundle Data Locally

`~bundler@1.0` is both a user workflow and an operator workflow. Users submit signed data items. The node verifies the item, caches it immediately, queues it, and later dispatches a bundle to Arweave according to operator thresholds.

## Check Bundler Settings

```bash
curl -sS "http://localhost:8734/~meta@1.0/info/format~hyperbuddy@1.0" | grep -i bundler -C 4
curl -sS "http://localhost:8734/~meta@1.0/info/bundler-ans104"
```

## Confirm Unsigned Data Is Rejected

```bash
curl -sS -X POST "http://localhost:8734/~bundler@1.0/tx" \
  -H "content-type: text/plain" \
  --data-binary "hello from an unsigned request"
```

Expected: an `invalid-item` response. The bundler requires a signed committed item.

## Submit A Signed Item

Create real signed ANS-104 bytes with HyperBEAM, then post the signed bytes:

```bash
cat > /tmp/hb-bundle-recipe-item.json <<'JSON'
{
  "data": "hello from the local bundler recipe",
  "content-type": "text/plain",
  "app-name": "hb-device-docs"
}
JSON
curl -sS -X POST \
  -H "content-type: application/json" \
  --data-binary @/tmp/hb-bundle-recipe-item.json \
  "http://localhost:8734/~message@1.0/commit&commitment-device=ans104@1.0&type=signed/~ans104@1.0/serialize" \
  -o /tmp/hb-bundle-recipe-signed-item.bin
curl -sS -X POST "http://localhost:8734/~bundler@1.0/tx?codec-device=ans104@1.0" \
  -H "content-type: application/octet-stream" \
  --data-binary @/tmp/hb-bundle-recipe-signed-item.bin
```

Expected for a valid signed item:

```json
{"id":"<item-id>","timestamp":<milliseconds>}
```

The item ID can be used in later cache/query reads if the node cached it successfully. Arweave permanence starts only after the bundler dispatches and the network confirms the bundle.

## Operator Checks

```bash
curl -sS "http://localhost:8734/~meta@1.0/info/format~hyperbuddy@1.0" | grep -i -E 'bundler|max|worker|meter|arweave'
curl -sS "http://localhost:8734/~meta@1.0/info/bundler-ans104"
```

Metering output depends on whether the node configured metering sessions and rates; the default edge node may expose a bundler route without enabling metering consumption.
