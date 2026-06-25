# Gzip Round Trip

This recipe proves a reversible transformation: message body to gzip bytes, then back to the original body.

## Short Payload

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~message@1.0&body=hello/~gzip@1.0/zip/~gzip@1.0/unzip/body"
```

Expected output: `hello`.

## Longer Payload

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~message@1.0&body=HyperBEAM-device-docs/~gzip@1.0/zip/~gzip@1.0/unzip/body"
```

Expected output: `HyperBEAM-device-docs`.

Avoid examples that write compressed bytes or headers to local files unless the recipe owns those files from the first step and the validator checks them.
