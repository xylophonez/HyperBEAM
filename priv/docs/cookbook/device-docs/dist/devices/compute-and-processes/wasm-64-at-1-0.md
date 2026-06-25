# ~wasm-64@1.0

A Memory-64 WASM execution device backed by WAMR through the BEAMR wrapper.

## When To Use It

- Run WASM process logic.
- Initialize and call a WASM executor stored in node memory.
- Snapshot WASM state for process replay.

## Action Keys

| Key | What it does |
|---|---|
| `init` | Load a WASM image from the process message and create an in-memory executor. |
| `compute` | Call the WASM executor with process and message input. |
| `snapshot` | Serialize WASM state. |
| `instance` | Loaded instance handle used by WASM execution paths. |
| `terminate` | Tear down the executor. |
| `import` | Resolve WASM import calls through HyperBEAM. |

## Local Examples

### Execute a WASM function directly

```text
curl -sS -X POST "http://localhost:8734/~wasm-64@1.0/compute" \
  -H 'wasm-function: fac' \
  -H 'wasm-params: [10]' \
  --data-binary @/path/to/test-64.wasm
```

Expected: the module is loaded, function `fac` is invoked with parameter `10`, and the result is returned or cached as WASM state.

### Continue from a prior hashpath/state

```text
HASHPATH="<hashpath-from-first-compute>"
curl -sS "http://localhost:8734/$HASHPATH/compute?wasm-function=fac&wasm-params=[11]"
```

Expected: `wasm-64@1.0` resumes from cached instance/snapshot state instead of initializing from scratch.

### Use WASM as a process execution device

```text
cat > /tmp/wasm-process.json <<'JSON'
{
  "device": "process@1.0",
  "execution-device": "wasm-64@1.0",
  "scheduler-device": "scheduler@1.0",
  "module": "<wasm-module-tx-id>",
  "wasm-function": "handle"
}
JSON
```

Expected: scheduled process messages call the module's handler through the process stack.

## Composition

- Use with `~wasi@1.0` for filesystem/stdout imports.
- Use as a process execution device under `~process@1.0`.

## Trust And Operation

WASM execution depends on the exact image, imports, state, and WAMR environment used by the node.

## Source

- Root module: `dev_wasm`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
