# Run An Inline Lua Transform

The old Arweave-to-Lua recipe depended on copycat state, local temporary files, and transaction data availability. This replacement keeps the useful device composition: post a Lua module inline, execute one function, and serialize the resulting message.

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

Use this as the public Lua fixture. Arweave-backed compute recipes need an explicit first step that imports or fetches the data and a validation step proving the target transaction bytes exist.
