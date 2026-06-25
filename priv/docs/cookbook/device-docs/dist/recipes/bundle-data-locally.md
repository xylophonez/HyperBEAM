# Inspect An ANS-104 Bundling Shape

Bundling is a write workflow: a real submission requires signed ANS-104 bytes and operator bundler configuration. The public recipe stays read-only and verifies the pieces a bundling example must use before a signed fixture is introduced.

## Inspect The ANS-104 Codec

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~ans104@1.0/info/schema"
```

Expected: a JSON schema object with codec operations such as `commit`, `serialize`, or `deserialize`.

## Build A Candidate Data Message

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~message@1.0&body=bundle-example&media-type=text-plain/~json@1.0/serialize"
```

Expected: JSON with `body` equal to `bundle-example` and `media-type` equal to `text-plain`.

A production bundler recipe must add a tested signing step that creates the item bytes in the same recipe, then post those bytes to a node whose bundler route is enabled. Do not publish examples that assume a pre-existing `/tmp` item file.
