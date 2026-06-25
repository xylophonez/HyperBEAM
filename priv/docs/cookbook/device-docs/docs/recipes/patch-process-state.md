# Patch A Message Key

`~patch@1.0` moves values between message keys so later devices see the shape they expect. This replacement recipe avoids POST bodies and local fixtures: all inputs are in the URL.

## Move `source` Into `body`

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~message@1.0&source=hello&body=old&from=source&to=body/~patch@1.0/all/body"
```

Expected output: `hello`.

## Inspect The Patched Message

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~message@1.0&source=hello&body=old&from=source&to=body/~patch@1.0/all/~json@1.0/serialize"
```

Expected: JSON where `body` is `hello`, `from` is `source`, and `to` is `body`.

For process examples, the same idea is useful before Lua/WASM compute and after compute before push. The public recipe stops at the deterministic key move; process state mutation needs a separate fixture.
