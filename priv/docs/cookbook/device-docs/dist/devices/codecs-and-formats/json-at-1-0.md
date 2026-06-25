# ~json@1.0

A JSON codec for serializing and deserializing HyperBEAM messages.

## When To Use It

- Return device output to ordinary clients.
- Return message shapes to shell scripts and browser clients.
- Bridge HyperBEAM messages with JavaScript tooling.

## Action Keys

| Key | What it does |
|---|---|
| `serialize` | Convert the current message to JSON. |
| `deserialize` | Convert JSON input into a message when called with a JSON body. |

## Local Examples

Inspect workflow examples show request, configuration, or operator command shapes. Run them only after providing the stated local prerequisites; the browser runner does not execute these blocks.

### Serialize a constructed message

```bash
curl -sS "http://localhost:8734/~message@1.0&greeting=hello&count+integer=42/~json@1.0/serialize"
```

Expected: JSON with `greeting` as a string and `count` as a number.

### Decode JSON request body into a message

```bash
curl -sS -X POST \
  --data-binary '{"greeting":"hello","count":42}' \
  "http://localhost:8734/~json@1.0/deserialize/serialize~json@1.0"
```

Expected: `deserialize` turns JSON body bytes into message keys, and the trailing `serialize~json@1.0` makes the decoded message visible to HTTP clients as JSON. Without the serialize step, the fields still exist on the message, but a browser-facing request may render the node's default HTML body.

### Use JSON as an API format for another device

```text
curl -sS "http://localhost:8734/~meta@1.0/info/~json@1.0/serialize"
```

Expected: a JSON-serialized node message. The point is the boundary: `~meta@1.0` returns a HyperBEAM message, and `~json@1.0` turns it into a client-readable body.

## Composition

- Use at the end of paths for clients.
- Use before external tools that expect JSON.

## Trust And Operation

JSON is a presentation codec. Verify signatures or commitments before trusting the content.

## Source

- Root module: `dev_json`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
