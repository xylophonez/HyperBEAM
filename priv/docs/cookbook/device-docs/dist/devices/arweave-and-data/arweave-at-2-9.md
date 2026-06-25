# ~arweave@2.9

The Arweave access device. It reads network status, blocks, transaction headers, raw data, chunks, prices, anchors, pending chunks, and posts signed transactions through the node route.

## When To Use It

- Read Arweave network metadata from the configured gateway route.
- Load transaction headers and raw payload bytes into HyperBEAM messages.
- Post signed L1 or ANS-104 data through the node policy.
- Support query, copycat, cache, and bundling workflows.

## Action Keys

| Key | What it does |
|---|---|
| `status` | Proxy the Arweave node `/info` endpoint. |
| `current` | Return current network/block information from the configured route. |
| `tx` | Read a transaction as an AO-Core message; POST signed TX or ANS-104 data when called with POST. |
| `raw` | Read raw transaction data and content metadata, including range reads. |
| `chunk` | Read an Arweave data chunk or byte range by offset; POST chunk JSON when called with POST. |
| `block` | Read a block by height or ID. |
| `price` | Ask the gateway for upload price for a byte count or target. |
| `tx_anchor` | Read the current transaction anchor. |
| `pending` | Read chunks for an unconfirmed transaction. |
| `post_chunk/post_tx_header/post_tx` | Upload helpers used by `chunk` and `tx`. |

## Local Examples

Inspect workflow examples show request, configuration, or operator command shapes. Run them only after providing the stated local prerequisites; the browser runner does not execute these blocks.

### Fetch raw Arweave data by transaction ID

```text
TXID="wKzEejXI5AlypYl82NYzgtBNIAOg10Ui0EWM4bkYRN4"
curl -sS "http://localhost:8734/~copycat@1.0/arweave?from=1936565&to=1936565&mode=write" >/dev/null
curl -sS "http://localhost:8734/~arweave@2.9/tx=$TXID?exclude-data=true"
curl -sSI "http://localhost:8734/~arweave@2.9/raw=$TXID"
curl -sS -H "Range: bytes=0-63" "http://localhost:8734/~arweave@2.9/raw=$TXID"
```

Expected: copycat first indexes the containing block, the tx call returns transaction metadata without loading the full data body, the `HEAD` call returns raw payload metadata such as content length/range support, and the range call returns the first bytes of the transaction data.

### Bring the containing block into the node, then read bytes

```text
curl -sS "http://localhost:8734/~copycat@1.0/arweave?from=1936565&to=1936565&mode=write"
curl -sS "http://localhost:8734/~copycat@1.0/arweave?from=1936565&to=1936565&mode=list" | grep "wKzEejXI5AlypYl82NYzgtBNIAOg10Ui0EWM4bkYRN4"
curl -sS -H "Range: bytes=0-31" "http://localhost:8734/~arweave@2.9/raw=wKzEejXI5AlypYl82NYzgtBNIAOg10Ui0EWM4bkYRN4"
```

Expected: `mode=write` copies block/TX offset facts into the local Arweave index; `mode=list` shows which transactions in that block are now indexed; `raw=...` can then read the transaction payload through HyperBEAM rather than a gateway URL.

### Use the raw-data headers as an offset source

```text
curl -sS "http://localhost:8734/~copycat@1.0/arweave?from=1936565&to=1936565&mode=write" >/dev/null
curl -sSI "http://localhost:8734/~arweave@2.9/raw=wKzEejXI5AlypYl82NYzgtBNIAOg10Ui0EWM4bkYRN4" \
  | grep -i -E 'offset|content-length|raw-id'
```

Expected: `offset`, `content-length`, and `raw-id` identify the Arweave byte range backing this transaction. Copycat and query workflows use these facts to move from indexed IDs to raw bytes.

### Quote price and anchor before upload

```bash
curl -sS "http://localhost:8734/~arweave@2.9/price?size=1024"
curl -sS "http://localhost:8734/~arweave@2.9/tx_anchor"
```

Expected: a Winston price quote and a current transaction anchor from the configured Arweave route. Use these when preparing direct L1 `tx@1.0` uploads.

## Composition

- Use `~copycat@1.0` and `~query@1.0` to find IDs, then `~arweave@2.9/tx` or `raw` to load them.
- Use `~copycat@1.0` to bring Arweave data into the local cache, then query locally.
- Use `~bundler@1.0` for local bundling service behavior; use `~arweave@2.9/tx` for direct transaction posting.

## Trust And Operation

Reads cross the local/remote boundary unless the data is already in local cache. Verify transaction commitments and block confirmations when applications depend on authenticity or finality.

## Source

- Root module: `dev_arweave`
- Helper modules: `dev_arweave_offset`, `dev_arweave_block_cache`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
