# Build A Message And Serialize It

This is the smallest useful HyperBEAM pipeline: construct a message, read fields from it, then serialize it for a client.

## Read Fields

```bash
curl -sS "http://localhost:8734/~message@1.0&greeting=hello/greeting"
curl -sS "http://localhost:8734/~message@1.0&count+integer=42/count"
```

Expected output:

```text
hello
42
```

## Serialize The Message

```bash
curl -sS "http://localhost:8734/~message@1.0&greeting=hello&count+integer=42/~json@1.0/serialize"
```

## Human View

```bash
curl -sS "http://localhost:8734/~message@1.0&greeting=hello&count+integer=42/format~hyperbuddy@1.0"
```

This pattern appears everywhere: a path first creates or loads a message, then another device transforms or renders it.
