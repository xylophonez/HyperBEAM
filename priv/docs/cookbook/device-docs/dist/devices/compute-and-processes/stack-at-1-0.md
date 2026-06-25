# ~stack@1.0

A composition device that runs a declared stack of devices in fold or map mode.

## When To Use It

- Build reusable pipelines from device names.
- Apply the same input across several devices.
- Wrap execution devices with patching, deduplication, or codecs.

## Action Keys

| Key | What it does |
|---|---|
| `device-stack` | The ordered list of devices to execute. |
| `fold mode` | Pass each result into the next device. |
| `map mode` | Run stack entries independently over the input. |
| `prefix/router helpers` | Support routing and prefix behavior for stack entries. |

## Local Examples

### Build a two-device transform pipeline

```text
HB="<local-node-with-stack-device>"
cat > /tmp/stack.json <<'JSON'
{
  "device": "stack@1.0",
  "device-stack": {
    "1": "gzip@1.0",
    "2": "json@1.0"
  },
  "body": "hello stack"
}
JSON
curl -sS -X POST --data-binary @/tmp/stack.json \
  "$HB/zip/serialize"
```

Expected: the request first executes gzip behavior, then JSON serialization over the result.

### Use stack for request preprocessing

```text
cat > /tmp/hb-stack-hook.flat <<'EOF'
on/request/device: stack@1.0
on/request/device-stack/1: rate-limit@1.0
on/request/device-stack/2: auth-hook@1.0
EOF
```

Expected: incoming requests pass through rate limiting before auth signing. Stack is how operators compose hook devices without hard-coding a new device.

### Run map mode over several devices

```text
HB="<local-node-with-stack-device>"
curl -sS -X POST -H 'content-type: application/json' \
  --data-binary '{"device":"stack@1.0","mode":"map","device-stack":{"1":"message@1.0","2":"json@1.0"},"body":"hello"}' \
  "$HB/body/~json@1.0/serialize"
```

Expected: map mode combines each device's result into one message instead of treating the stack as a strict pipeline.

## Composition

- Use with `~patch@1.0` to normalize input between stack entries.
- Use with `~dedup@1.0`, `~lua@5.3a`, and codec devices.

## Trust And Operation

A stack is as trustworthy as the devices it calls and the message that defines its stack.

## Source

- Root module: `dev_stack`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
