# Query Local Cache

`~query@1.0` searches local cache and store indexes. It does not magically know remote data; first the node must have indexed or cached messages through copycat, Arweave reads, bundling, scheduler state, or trusted cache writes.

## Check Index Readiness

```bash
curl -sS "http://localhost:8734/~meta@1.0/info/preloaded-devices-index"
curl -sS "http://localhost:8734/~meta@1.0/info/format~hyperbuddy@1.0" | grep -i -E 'store|cache|match|index'
```

## Count Local Index Entries

```bash
curl -sS "http://localhost:8734/~query@1.0/all?return=count"
curl -sS "http://localhost:8734/~query@1.0/all?return=boolean"
```

Expected: the first command returns a count of entries currently visible to the local query device, and the second returns `true` when any entries are visible.

Return modes:

| Mode | Use |
|---|---|
| `count` | Check whether matches exist without loading them. |
| `paths` | Return cache paths or IDs. |
| `messages` | Load full matched messages. |
| `first-path` | Return one path for a follow-up cache read. |
| `first-message` | Return one loaded message. |
| `boolean` | Return true/false. |

## Copy Data Before Narrow Queries

```bash
curl -sS "http://localhost:8734/~copycat@1.0/arweave?from=1936565&to=1936565&mode=write"
curl -sS "http://localhost:8734/~copycat@1.0/arweave?from=1936565&to=1936565&mode=list"
```

Expected: copycat imports one real Arweave block, then lists the transaction IDs it indexed. Use that list with `~arweave@2.9/tx` or `~arweave@2.9/raw` for deterministic reads. Narrow key/value query filters are node-index dependent; validate them on your operator node before publishing them as application paths.
