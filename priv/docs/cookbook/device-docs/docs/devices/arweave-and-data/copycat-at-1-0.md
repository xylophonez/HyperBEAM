# ~copycat@1.0

An indexing orchestrator. It copies messages from foreign sources into the local HyperBEAM cache so local query, read, and compute paths can operate on them.

## When To Use It

- Pull Arweave data into a local cache.
- Walk recent Arweave blocks and index transaction data.
- Prepare a node for local query/read workflows without repeatedly hitting remote gateways.

## Action Keys

| Key | What it does |
|---|---|
| `graphql` | Build or accept a GraphQL query, fetch all pages from a gateway, parse returned transactions into messages, and write them to cache. |
| `arweave` | Fetch blocks from the configured Arweave node. By default it walks backward from `from` until it reaches already indexed data; `to` makes the range explicit. |
| `mode=list` | For the Arweave engine, list indexed/not-indexed transaction status for a block range without writing new data. |
| `mode=write` | Fetch and write missing block/transaction data into local indexes. |

## Local Examples

Inspect workflow examples show request, configuration, or operator command shapes. Run them only after providing the stated local prerequisites; the browser runner does not execute these blocks.

### Copy one Arweave block into local indexes

```text
curl -sS "http://localhost:8734/~copycat@1.0/arweave?from=1749502&to=1749502&mode=write"
curl -sS "http://localhost:8734/~copycat@1.0/arweave?from=1749502&to=1749502&mode=list"
```

Expected: `mode=write` fetches the block header and writes transaction/data-item offsets into the node's Arweave index; `mode=list` reports indexed and not-yet-indexed transactions for that block. This is the central copycat use case: it brings network facts into the node so later reads can be local/index-backed.

### Copy recent blocks backwards until existing coverage

```text
TIP=$(curl -sS "http://localhost:8734/~arweave@2.9/current/height")
curl -sS "http://localhost:8734/~copycat@1.0/arweave?from=$TIP&mode=write"
```

Expected: copycat walks backwards from the current block and stops when it reaches already indexed data. Operators use this to keep a local node warm without choosing exact historical ranges every time.

### Query copied data locally

```text
curl -sS "http://localhost:8734/~copycat@1.0/arweave?from=1936565&to=1936565&mode=write"
curl -sS "http://localhost:8734/~copycat@1.0/arweave?from=1936565&to=1936565&mode=list"
```

Expected: the first command imports one real Arweave block into local indexes; the second command lists the transaction IDs now indexed for that block. This is the basic operator loop: copy data first, then read or compute over known IDs.

### Prove copied offsets unlock raw reads

```text
TXID="ptBC0UwDmrUTBQX3MqZ1lB57ex20ygwzkjjCrQjIx3o"
curl -sS "http://localhost:8734/~copycat@1.0/arweave?from=1749502&to=1749502&mode=write"
curl -sSI "http://localhost:8734/~arweave@2.9/raw=$TXID" | grep -i -E 'content-length|accept-ranges|status|ao-types'
```

Expected: after block indexing, the Arweave device has enough offset information to answer raw-data metadata/range requests for transactions in that block.

## Composition

- Run copycat first, then use `~query@1.0` to search local cache.
- Use returned IDs with `~cache@1.0/read` or `~arweave@2.9/raw`.
- Schedule recurring copycat jobs with `~cron@1.0` on operator nodes.

## Trust And Operation

Copycat changes local cache state. The copied data can still be verified by its original commitments; the act of indexing only makes it locally discoverable.

## Source

- Root module: `dev_copycat`
- Helper modules: `dev_copycat_arweave`, `dev_copycat_graphql`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
