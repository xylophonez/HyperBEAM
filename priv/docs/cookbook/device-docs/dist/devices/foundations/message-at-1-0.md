# ~message@1.0

The basic message construction and field access device. It turns URL fields into a HyperBEAM message and lets paths read those fields.

## When To Use It

- Create small messages in a URL.
- Demonstrate typed fields and path access.
- Prepare input for codec, compute, and recipe examples.

## Action Keys

| Key | What it does |
|---|---|
| `default field access` | A path segment reads the matching key from the message. |
| `typed keys` | Keys such as `count+integer` create typed values instead of plain text. |
| `set/remove/keys` | Merge, unset, or list public keys on a message. |

## Local Examples

### Build a typed message and read fields

```bash
curl -sS "http://localhost:8734/~message@1.0&greeting=hello&count+integer=42/count"
curl -sS "http://localhost:8734/~message@1.0&greeting=hello&count+integer=42/greeting"
```

Expected: `42` and `hello`.

### List public keys for a constructed message

```bash
curl -sS "http://localhost:8734/~message@1.0&greeting=hello&role=operator/keys/~json@1.0/serialize"
```

Expected: a list containing public keys such as `greeting` and `role`. This is useful before committing only a selected subset of keys.

### Calculate and verify IDs/commitments

```bash
curl -sS "http://localhost:8734/~message@1.0&body=commit-me/id"
curl -sS "http://localhost:8734/~message@1.0&body=commit-me/commit&commitment-device=httpsig@1.0&type=hmac-sha256&scheme=secret&secret=s3cr3t/verify&commitment-device=httpsig@1.0&type=hmac-sha256&scheme=secret&secret=s3cr3t"
```

Expected: a stable ID for the message, and `true` for verification of the committed message.

## Composition

- Use as the first segment in recipes to create controlled input.
- Pair with `~json@1.0`, `~gzip@1.0`, `~query@1.0`, and compute devices.

## Trust And Operation

Message examples are local and deterministic. Signed messages add commitment and signer verification on top of this base shape.

## Source

- Root module: `dev_message`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
