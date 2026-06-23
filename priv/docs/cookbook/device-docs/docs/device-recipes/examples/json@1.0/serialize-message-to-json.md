# Serialize A Message To JSON

Serialize a constructed HyperBEAM message with `~json@1.0/serialize` and inspect the JSON-native fields returned to an HTTP client.

Source test: `dev_json:deeply_nested_typed_keys_test/0`.

Prerequisites:

- Local HyperBEAM node at `http://localhost:8734`.
- Optional: `jq` for compact inspection.

## 1. Build A Typed Message And Serialize It

```bash
HB=${HB:-http://localhost:8734}

curl -sS "$HB/~message@1.0&greeting=hello&count+integer=42/~json@1.0/serialize" \
  | jq '{greeting, count}'
```

Expected:

```json
{
  "greeting": "hello",
  "count": 42
}
```

## 2. Check The HTTP Body Is JSON

```bash
HB=${HB:-http://localhost:8734}

curl -sSI "$HB/~message@1.0&greeting=hello&count+integer=42/~json@1.0/serialize" \
  | grep -i '^content-type:'
```

Expected:

```text
content-type: application/json
```
