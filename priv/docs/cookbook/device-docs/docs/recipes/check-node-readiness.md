# Check Docs-Test Readiness

Use this before running examples. It proves that the docs node is serving the node index and that device schema routes resolve through the same on-weave spec map used by the UI.

## Node Docs Index

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/info"
```

Expected: a JSON node documentation index with boilerplate pages and the loaded device list.

## Message Device Schema

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~message@1.0/info/schema"
```

Expected: a JSON schema object containing keys such as `commit`, `set`, `get`, and `keys`.

## Gzip Device Schema

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~gzip@1.0/info/schema"
```

Expected: a JSON schema object containing `zip` and `unzip`.

This recipe does not read private operator config keys. Use it as a public smoke test for the docs pipeline, not as an authority check for a production node.
