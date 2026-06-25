# ~manifest@1.0

An Arweave path-manifest resolver for v1 manifests. It maps request paths to data items described by a manifest message.

## When To Use It

- Serve bundled web assets by manifest path.
- Resolve an index file from a manifest.
- Cast legacy manifest content into a HyperBEAM device flow.

## Action Keys

| Key | What it does |
|---|---|
| `index` | Return the fallback index entry. |
| `request` | Route a path through the manifest to the associated data. |
| `on/request hook` | Detect legacy manifests and cast them to this device. |

## Local Examples

Inspect workflow examples show request, configuration, or operator command shapes. Run them only after providing the stated local prerequisites; the browser runner does not execute these blocks.

### Resolve an index path from a manifest message

```text
HB="<local-node-with-manifest-cache>"
cat > /tmp/manifest.json <<'JSON'
{
  "device": "manifest@1.0",
  "content-type": "application/x.arweave-manifest+json",
  "data": "{\"manifest\":\"arweave/paths\",\"version\":\"0.2.0\",\"index\":{\"path\":\"index.html\"},\"paths\":{\"index.html\":{\"id\":\"ptBC0UwDmrUTBQX3MqZ1lB57ex20ygwzkjjCrQjIx3o\"}}}"
}
JSON
curl -sS -X POST --data-binary @/tmp/manifest.json \
  "$HB/~manifest@1.0/index/~json@1.0/serialize"
```

Expected: `index` follows the manifest's `index.path` to `paths/index.html` and returns the linked message if it is available in cache.

### Resolve a specific asset path

```text
HB="<local-node-with-manifest-cache>"
curl -sS -X POST --data-binary @/tmp/manifest.json \
  "$HB/~manifest@1.0/index.html/~json@1.0/serialize"
```

Expected: the manifest device maps `index.html` to its configured ID. If the ID is not in local cache, load it through `~arweave@2.9` or copycat first.

### Serve a legacy manifest by ID

```text
HB="<local-node-with-manifest-cache>"
MANIFEST_ID="<manifest_tx_id>"
curl -sS "$HB/$MANIFEST_ID/index"
curl -sS "$HB/$MANIFEST_ID/assets/app.js"
```

Expected: the request hook casts cached `application/x.arweave-manifest` data to `manifest@1.0`, then routes the remaining path through the manifest.

## Composition

- Use after `~arweave@2.9/tx` loads a manifest transaction.
- Use with `~cache@1.0` for locally cached manifest assets.

## Trust And Operation

A manifest routes paths to IDs; verify the manifest transaction and target data according to your application needs.

## Source

- Root module: `dev_manifest`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
