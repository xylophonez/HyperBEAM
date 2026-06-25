# ~gzip@1.0

A compression device that zips and unzips message bodies.

## When To Use It

- Compress payloads before storage or transport.
- Round-trip compressed message bodies.
- Demonstrate reversible path composition.

## Action Keys

| Key | What it does |
|---|---|
| `zip` | Compress the `body` field. |
| `unzip` | Decompress the `body` field. |

## Local Examples

### Compress a message body

```text
curl -sS -D /tmp/hb-gzip-headers.txt \
  "http://localhost:8734/~message@1.0&body=hello-from-hyperbeam/~gzip@1.0/zip/body" \
  -o /tmp/hb-gzip-body.bin
sed -n '/^content-encoding:/Ip;/^content-length:/Ip' /tmp/hb-gzip-headers.txt
wc -c /tmp/hb-gzip-body.bin
```

Expected: `content-encoding` is `gzip` and the body file contains compressed bytes.

### Decompress the same body

```bash
curl -sS "http://localhost:8734/~message@1.0&body=hello-from-hyperbeam/~gzip@1.0/zip/~gzip@1.0/unzip/body"
```

Expected: `hello-from-hyperbeam`.

### Decompress a gzip payload from the shell

```text
printf 'payload from stdin' | gzip -c >/tmp/payload.gz
curl -sS -X POST -H 'content-encoding: gzip' --data-binary @/tmp/payload.gz \
  "http://localhost:8734/~gzip@1.0/unzip/body"
```

Expected: `payload from stdin`. This is the use case for relayed or cached payloads that already carry `content-encoding: gzip`.

## Composition

- Use before bundling, cache writes, or relay when payload size matters.
- Use after raw reads when the payload is gzip-compressed.

## Trust And Operation

Compression is deterministic for the input bytes, but it does not authenticate them.

## Source

- Root module: `dev_gzip`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
