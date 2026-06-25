# ~structured@1.0

A rich structured codec for typed HyperBEAM messages, including integers, floats, atoms, lists, and nested values.

## When To Use It

- Preserve typed message values across serialization boundaries.
- Commit or verify structured message forms.
- Convert between TABM and typed representations.

## Action Keys

| Key | What it does |
|---|---|
| `to` | Convert a message into structured form. |
| `from` | Convert structured form back into a message. |
| `encode/decode` | Encode or decode structured fields. |
| `commit/verify` | Commit or verify structured message commitments. |

## Local Examples

Inspect workflow examples show request, configuration, or operator command shapes. Run them only after providing the stated local prerequisites; the browser runner does not execute these blocks.

### Encode rich types into `ao-types`

```bash
curl -sS -X POST -H 'content-type: application/json' \
  --data-binary '{"count":42,"ratio":1.5,"items":["a","b"],"ok":true}' \
  "http://localhost:8734/~structured@1.0/from/~json@1.0/serialize"
```

Expected: scalar values become TABM-safe binaries and `ao-types` records which keys were integers, floats, atoms, or lists.

### Decode `ao-types` back to rich values

```bash
curl -sS -X POST -H 'content-type: application/json' \
  --data-binary '{"count":"42","ok":"true","ao-types":"count=\"integer\", ok=\"atom\""}' \
  "http://localhost:8734/~structured@1.0/to/~json@1.0/serialize"
```

Expected: `count` is an integer and `ok` is an atom/boolean-like value after decoding.

### Limit the encoded type set

```text
curl -sS -X POST -H 'content-type: application/json' \
  --data-binary '{"count":42,"ratio":1.5,"items":["a","b"]}' \
  "http://localhost:8734/~structured@1.0/from&encode-types=integer,list/~json@1.0/serialize"
```

Expected: only selected rich types are encoded into `ao-types`; others pass through according to downstream codec behavior.

## Composition

- Use under commitment devices such as `~httpsig@1.0` and Arweave TX codecs.
- Use before JSON-Iface when typed values need preservation.

## Trust And Operation

The codec preserves shape; trust comes from the commitment or signer wrapped around the encoded message.

## Source

- Root module: `dev_structured`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
