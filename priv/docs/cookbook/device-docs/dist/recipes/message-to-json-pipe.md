# Build A Message And Serialize It

This is the smallest useful HyperBEAM pipeline: construct a message, read fields from it, then serialize the same message for a client.

## Read Fields

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~message@1.0&greeting=hello/greeting"
curl -fsS "$HB/~message@1.0&count+integer=42/count"
```

Expected output: `hello` and `42`.

## Serialize The Message

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~message@1.0&greeting=hello&count+integer=42/~json@1.0/serialize"
```

Expected: a JSON object with `greeting` equal to `hello` and `count` equal to `42`.

This pattern appears everywhere: a path creates or loads a message, then another device transforms or renders it.
