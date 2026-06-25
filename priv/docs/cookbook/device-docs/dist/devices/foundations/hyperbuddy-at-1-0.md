# ~hyperbuddy@1.0

A human-readable formatter for HyperBEAM messages. It is useful while exploring paths, reading node state, and debugging recipes.

## When To Use It

- Read large messages without writing a client.
- Debug path composition and device outputs.
- Preview node configuration and cache/query responses.

## Action Keys

| Key | What it does |
|---|---|
| `format~hyperbuddy@1.0` | Render the current message or result for a person. |
| `body rendering` | Shows keys, nested values, and message metadata in a readable form. |

## Local Examples

### Render a message for a human

```bash
curl -sS "http://localhost:8734/~message@1.0&greeting=hello&count+integer=42/format~hyperbuddy@1.0"
```

Expected: an HTML/text human-readable representation of the message and its typed fields.

### Render query results while debugging cache behavior

```bash
curl -sS "http://localhost:8734/~query@1.0/all?return=count"
```

Expected: a local query count. Use Hyperbuddy for structured messages; plain scalar results such as counts are already readable.

### Use JSON when a program consumes the result

```bash
curl -sS "http://localhost:8734/~message@1.0&greeting=hello&count+integer=42/~json@1.0/serialize"
```

Expected: use `hyperbuddy` for operator eyes and `json@1.0` for scripts.

## Composition

- Place at the end of exploratory paths.
- Replace with `~json@1.0/serialize` when building machine clients.

## Trust And Operation

Hyperbuddy changes presentation, not the underlying message semantics.

## Source

- Root module: `dev_hyperbuddy`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
