# ~multipass@1.0

A repass trigger device. It can cause evaluation to pass through a workflow multiple times until a configured counter is reached.

## When To Use It

- Model retry-like evaluation loops.
- Drive multi-stage process evaluation.
- Test stack behavior across repeated passes.

## Action Keys

| Key | What it does |
|---|---|
| `repass` | Trigger another pass through evaluation. |
| `counter/limit` | Track how many passes have occurred and when to stop. |

## Local Examples

Inspect workflow examples show request, configuration, or operator command shapes. Run them only after providing the stated local prerequisites; the browser runner does not execute these blocks.

### Repeat a stack for multiple passes

```text
HB="<local-node-with-multipass-stack>"
cat > /tmp/multipass-stack.json <<'JSON'
{
  "device": "stack@1.0",
  "device-stack": {"1":"message@1.0", "2":"multipass@1.0"},
  "passes": 3,
  "counter": 0
}
JSON
curl -sS -X POST --data-binary @/tmp/multipass-stack.json \
  "$HB/counter/~json@1.0/serialize"
```

Expected: `multipass@1.0` asks the resolver to run another pass until the pass count reaches `passes`.

### Combine with dedup safely

```text
cat > /tmp/dedup-multipass-stack.json <<'JSON'
{
  "device": "stack@1.0",
  "dedup-subject": "request",
  "device-stack": {"1":"dedup@1.0", "2":"multipass@1.0"},
  "passes": 2
}
JSON
```

Expected: dedup checks only the first pass; multipass can still repeat the workflow across passes.

### Stop at one pass when no repeat is requested

```text
Base message:
  device: multipass@1.0
  passes: 1
  pass: 1

Request:
  path: compute
```

Expected: no repass occurs when the current pass already satisfies the configured pass count.

## Composition

- Use with `~stack@1.0`, `~patch@1.0`, and process compute flows.

## Trust And Operation

Loops can amplify work. Apply limits before using on public or paid nodes.

## Source

- Root module: `dev_multipass`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
