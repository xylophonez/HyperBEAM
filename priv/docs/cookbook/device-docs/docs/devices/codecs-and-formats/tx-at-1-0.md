# ~tx@1.0

The Arweave L1 transaction codec. It converts Arweave transaction records to and from HyperBEAM message form.

## When To Use It

- Read Arweave transactions as messages.
- Prepare L1 transactions for posting through `~arweave@2.9`.
- Verify transaction-shaped commitments and read transaction headers/tags.

## Action Keys

| Key | What it does |
|---|---|
| `to/from` | Convert between HyperBEAM and Arweave transaction record forms. |
| `serialize/deserialize` | Encode or decode transaction JSON/bytes. |
| `commit/verify` | Commit or verify transaction-shaped messages. |

## Local Examples

### Read an Arweave transaction as JSON

```bash
TXID="ptBC0UwDmrUTBQX3MqZ1lB57ex20ygwzkjjCrQjIx3o"
curl -sS "http://localhost:8734/~arweave@2.9/tx=$TXID?exclude-data=true/serialize~json@1.0"
```

Expected: the transaction body as JSON. HyperBEAM reads the L1 transaction, maps it into message form through `tx@1.0`, and serializes the resulting message body.

### Inspect the transaction commitment headers

```text
TXID="ptBC0UwDmrUTBQX3MqZ1lB57ex20ygwzkjjCrQjIx3o"
curl -sS "http://localhost:8734/~arweave@2.9/tx=$TXID?exclude-data=true" -D - -o /dev/null \
  | grep -i -E '^(status|content-type|data_size|reward|anchor|ao-types|signature-input):'
```

Expected: headers including `signature-input` with `alg="tx@1.0/rsa-pss-sha256"`, plus transaction fields such as `anchor`, `data_size`, and `reward`.

### Fetch the raw data behind the same transaction

```text
TXID="ptBC0UwDmrUTBQX3MqZ1lB57ex20ygwzkjjCrQjIx3o"
curl -sSI "http://localhost:8734/~arweave@2.9/raw=$TXID" \
  | grep -i -E '^(status|content-type|content-length|accept-ranges|raw-id|ao-types):'
```

Expected: raw-data headers for the same transaction. Use this with the first two examples when you need to separate the transaction envelope from the stored bytes.

## Composition

- Use with `~arweave@2.9/tx` and `~arweave@2.9/raw`.
- Use with `~copycat@1.0` and `~query@1.0` output that references Arweave transaction IDs.

## Trust And Operation

A TX codec view is not the same as network confirmation. Check status and commitments separately.

## Source

- Root module: `dev_tx`
- Helper modules: `dev_tx_from`, `dev_tx_to`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
