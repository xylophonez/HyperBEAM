# ~dedup@1.0

A stream helper that skips duplicate messages during evaluation.

## When To Use It

- Prevent repeated process outputs.
- Filter duplicate assignments or events.
- Build idempotent device stacks.

## Action Keys

| Key | What it does |
|---|---|
| `status=skip` | Mark duplicate items as skipped. |
| `pass` | Keys allowed to pass through. |
| `subject-key` | The key used to decide duplicate identity. |

## Local Examples

### Deduplicate repeated requests in a stack

```text
HB="<local-node-with-dedup-stack>"
cat > /tmp/dedup-stack.json <<'JSON'
{
  "device": "stack@1.0",
  "dedup-subject": "request",
  "device-stack": {
    "1": "dedup@1.0",
    "2": "message@1.0"
  },
  "result": "INIT"
}
JSON
curl -sS -X POST --data-binary @/tmp/dedup-stack.json \
  "$HB/append&bin=_/~json@1.0/serialize"
```

Expected: the first request is allowed through and records the request subject in the `dedup` trie. Replaying the same request against the resulting state returns `skip` instead of executing downstream devices again.

### Deduplicate by body instead of entire request

```text
HB="<local-node-with-dedup-stack>"
curl -sS -X POST -H 'content-type: application/json' \
  --data-binary '{"device":"dedup@1.0","dedup-subject":"body","body":{"id":"same-work"}}' \
  "$HB/run/~json@1.0/serialize"
```

Expected: messages with the same `body` hash are treated as the same work item even if other request keys differ.

### Use with multipass without blocking later passes

```text
cat > /tmp/dedup-multipass.json <<'JSON'
{
  "device": "stack@1.0",
  "dedup-subject": "request",
  "device-stack": {"1":"dedup@1.0", "2":"multipass@1.0"},
  "passes": 2
}
JSON
```

Expected: `dedup@1.0` only runs the first pass, so a legitimate `multipass@1.0` workflow can repeat across passes while duplicate external assignments are still suppressed.

## Composition

- Use inside `~stack@1.0` or process output handling before `~push@1.0`.

## Trust And Operation

Deduplication policy depends on the subject key and process context.

## Source

- Root module: `dev_dedup`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
