# Deserialize A JSON Field

Parse a JSON document stored in a message field with `~json@1.0/deserialize`, then serialize the decoded message back to JSON for inspection.

Source test: `dev_json:decode_with_atom_test/0`.

Prerequisites:

- Local HyperBEAM node at `http://localhost:8734`.
- Optional: `jq` for compact inspection.

## 1. Decode The Default `body` Field

```bash
HB=${HB:-http://localhost:8734}
JSON='%7B%22greeting%22%3A%22hello%22%2C%22count%22%3A42%7D'

curl -sS "$HB/~message@1.0&body=$JSON/~json@1.0/deserialize/serialize~json@1.0" \
  | jq '{greeting, count}'
```

Expected:

```json
{
  "greeting": "hello",
  "count": 42
}
```

## 2. Decode A Named Target Field

```bash
HB=${HB:-http://localhost:8734}
JSON='%7B%22greeting%22%3A%22hello%22%2C%22count%22%3A42%7D'

curl -sS "$HB/~message@1.0&payload=$JSON/~json@1.0/deserialize&target=payload/serialize~json@1.0" \
  | jq '.greeting == "hello" and .count == 42'
```

Expected:

```text
true
```
