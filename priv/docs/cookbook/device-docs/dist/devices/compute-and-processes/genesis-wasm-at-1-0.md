# ~genesis-wasm@1.0

A legacy AO process environment implemented on HyperBEAM infrastructure.

## When To Use It

- Run older Genesis-style WASM process flows and read their output state.
- Bridge legacy AO process assumptions into current device composition.
- Load latest checkpoints for compatible processes.

## Action Keys

| Key | What it does |
|---|---|
| `init` | Initialize legacy WASM process state. |
| `compute` | Compute a message against the process. |
| `snapshot` | Return state snapshot. |
| `latest_checkpoint` | Load latest checkpoint when available. |
| `import` | Resolve imports used by the environment. |

## Local Examples

Inspect workflow examples show request, configuration, or operator command shapes. Run them only after providing the stated local prerequisites; the browser runner does not execute these blocks.

### Define a Genesis-WASM process shell

```text
cat > /tmp/genesis-process.json <<'JSON'
{
  "device": "process@1.0",
  "execution-device": "genesis-wasm@1.0",
  "scheduler-device": "scheduler@1.0",
  "module": "<wasm-module-tx-id>",
  "function": "handle"
}
JSON
curl -sS -X POST -H 'content-type: application/json' --data-binary @/tmp/genesis-process.json \
  "http://localhost:8734/~process@1.0/now/~json@1.0/serialize"
```

Expected: on a node with the referenced WASM module available, process evaluation initializes legacy Genesis WASM state.

### Send a compute message to that process

```text
PROCESS_ID="<process-definition-id>"
curl -sS -X POST "http://localhost:8734/$PROCESS_ID~process@1.0/compute" \
  -H 'action: Eval' \
  --data-binary 'return 1 + 1'
```

Expected: the process stack invokes the Genesis WASM execution device with the posted message.

### Migrate new work toward wasm-64

```text
curl -sS "http://localhost:8734/~wasm-64@1.0/content-type"
```

Expected: for new processes prefer `wasm-64@1.0`; keep `genesis-wasm@1.0` for compatibility with older process definitions.

## Composition

- Use only for processes that expect this legacy environment.
- Prefer `~wasm-64@1.0` for new Memory-64 WASM process work.

## Trust And Operation

Legacy compatibility adds assumptions. Verify the process definition and checkpoint source.

## Source

- Root module: `dev_genesis_wasm`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
