# ~wasi@1.0

A virtual filesystem device plus WASI preview1-compatible imports for WASM modules.

## When To Use It

- Provide files, stdout, and clocks to WASM execution.
- Represent a filesystem as a HyperBEAM message map.
- Read stdout after WASM compute.

## Action Keys

| Key | What it does |
|---|---|
| `init` | Initialize the virtual filesystem. |
| `stdout` | Return stdout buffer from state. |
| `fd_read/fd_write/path_open/clock_time_get` | WASI preview1 import handlers used by WASM modules. |

## Local Examples

### Pass WASI args/env to a WASM process

```bash
cat > /tmp/wasi-process.json <<'JSON'
{
  "device": "process@1.0",
  "execution-device": "wasm-64@1.0",
  "wasi-device": "wasi@1.0",
  "wasi-args": ["program", "--help"],
  "wasi-env": {"MODE":"demo"},
  "module": "<wasm-module-id>"
}
JSON
```

Expected: when `wasm-64@1.0` runs the module, `wasi@1.0` supplies args/env and captures stdout/stderr according to process configuration.

### Read stdout after compute

```bash
PROCESS_ID="<wasi-process-id>"
curl -sS "http://localhost:8734/$PROCESS_ID~process@1.0/compute/results/stdout"
```

Expected: bytes written by the WASM module to stdout, if the module and process definition use WASI.

### Use a local file-less WASI module first

```bash
curl -sS "http://localhost:8734/~meta@1.0/info/format~hyperbuddy@1.0" \
  | grep -i -E 'wasm|wasi'
```

Expected: confirm the node's WASM/WASI-related runtime settings before testing modules that expect filesystem or socket access.

## Composition

- Use under `~wasm-64@1.0` and process stacks that run WASM.

## Trust And Operation

WASI state is part of execution state; verify the process state and image before trusting output.

## Source

- Root module: `dev_wasi`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
