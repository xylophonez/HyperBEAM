# Run An Inline Lua Transform

This recipe posts a Lua module inline, executes one function, and serializes the resulting message without local files or preloaded transaction state.

## Run The Transform

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS -X POST \
  -H 'content-type: application/json' \
  --data-binary '{"device":"lua@5.3a","content-type":"application/lua","body":"function greet(base, req, opts) return { body = \"hello \" .. (req.name or \"world\") } end"}' \
  "$HB/greet/body?name=hyperbeam"
```

Expected output: `hello hyperbeam`.

## Serialize The Result

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS -X POST \
  -H 'content-type: application/json' \
  --data-binary '{"device":"lua@5.3a","content-type":"application/lua","body":"function greet(base, req, opts) return { body = \"hello \" .. (req.name or \"world\") } end"}' \
  "$HB/greet/serialize~json@1.0?name=hyperbeam"
```

Expected: JSON with `body` equal to `hello hyperbeam`.

For Arweave-backed Lua compute, add a first step that imports or fetches the source transaction data and a validation step that proves the expected bytes are present before the transform runs.
