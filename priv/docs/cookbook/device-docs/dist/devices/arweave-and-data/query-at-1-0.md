# ~query@1.0

The local discovery engine. It searches supported stores and cache indexes, and it also implements an Arweave GraphQL-compatible query layer over indexed local data.

## When To Use It

- Find message IDs or cache paths by key/value criteria.
- Ask whether matching local data exists before loading it.
- Serve GraphQL transaction searches from local indexes populated by copycat or cache writes.
- Find IDs, then load full messages through `~cache@1.0` or data bytes through `~arweave@2.9`.

## Action Keys

| Key | What it does |
|---|---|
| `all` | Match all searchable keys in the request message. |
| `base` | Match keys from the base message. |
| `only` | Match only the keys named by the `only` field. |
| `return=count` | Return a count of matches. |
| `return=paths` | Return cache paths or IDs. |
| `return=messages` | Load and return full matched messages. |
| `return=first-path / first-message` | Return only the first match. |
| `return=boolean` | Return whether any match exists. |
| `graphql` | Handle Arweave GraphQL-style transaction and block queries over local indexes. |
| `has_results` | Return whether a GraphQL response contains transaction edges. |

## Local Examples

### Count local index entries

```bash
curl -sS "http://localhost:8734/~query@1.0/all?return=count"
```

Expected: a numeric count of entries currently visible to the local query device. This is the cheapest way to check whether the query device has any local index coverage.

### Ask for a boolean readiness check

```bash
curl -sS "http://localhost:8734/~query@1.0/all?return=boolean"
```

Expected: `true` or `false`. This mode is useful for hooks and route policies that need to know whether local query has any matching data without loading all matches.

### Query data imported by copycat

```bash
curl -sS "http://localhost:8734/~copycat@1.0/arweave?from=1936565&to=1936565&mode=write"
curl -sS "http://localhost:8734/~copycat@1.0/arweave?from=1936565&to=1936565&mode=list"
```

Expected: copycat imports a real block, then lists the transaction IDs it indexed. Use those IDs with `~arweave@2.9/tx` or `~arweave@2.9/raw`. Narrow key/value filters depend on the indexes available on the operator node, so validate them before treating them as application API paths.

## Composition

- Use `~copycat@1.0` to populate local indexes, then query them.
- Use query paths with `~cache@1.0/read` to load full messages.
- Use query output as input to Lua or WASM compute so processes operate on discovered data.

## Trust And Operation

Query is a read/discovery layer. It does not fetch remote data by itself except through its GraphQL implementation over configured local indexes; write/indexing work belongs to copycat, cache writers, or Arweave ingestion.

## Source

- Root module: `dev_query`
- Helper modules: `dev_query_arweave`, `dev_query_graphql`, `dev_query_test_vectors`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
