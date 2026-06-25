# ~cache@1.0

The local cache read/write device. It reads IDs or store paths, honors requested accept formats, and allows writes only from configured cache writers.

## When To Use It

- Read cached messages or bytes by path.
- Convert cached messages into client formats such as `application/aos-2`.
- Let trusted writers add, link, or group local cache entries.

## Action Keys

| Key | What it does |
|---|---|
| `read` | Read a cache location named by the `read` key. |
| `write` | Write a binary or store-shaped message; requires a trusted signer in `cache_writers`. |
| `link` | Link one store path to another; trusted-writer only. |
| `group` | Group cache paths; trusted-writer only. |

## Local Examples

### Read a known ID from the local cache

```bash
ID=$(curl -sS "http://localhost:8734/~meta@1.0/info/preloaded-devices-index")
curl -sS "http://localhost:8734/~cache@1.0/read&path=$ID/~json@1.0/serialize"
```

Expected: the cached preloaded device index if present in this node's store.

### Write a message as an authorized cache writer

```text
curl -sS -X POST -H 'content-type: application/json' \
  --data-binary '{"device":"message@1.0","body":"cache me","kind":"demo"}' \
  "http://localhost:8734/~cache@1.0/write/~json@1.0/serialize"
```

Expected: success only if the signer is in `cache_writers`; otherwise the response rejects the write. Cache writes are operator-controlled because they affect what future queries can find.

### Link one cache path to another

```text
curl -sS "http://localhost:8734/~cache@1.0/link?from=<source-cache-path>&to=aliases/demo-message"
curl -sS "http://localhost:8734/~cache@1.0/read?path=aliases/demo-message"
```

Expected: the alias path resolves to the same cached value after an authorized link operation.

## Composition

- Use after `~query@1.0` returns paths or IDs.
- Use after `~copycat@1.0` indexes remote data into local stores.
- Use with `~json-iface@1.0` when clients need AOS-style JSON.

## Trust And Operation

Reads are local store state. Writes affect future local resolution and should be limited to trusted signers.

## Source

- Root module: `dev_cache`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
