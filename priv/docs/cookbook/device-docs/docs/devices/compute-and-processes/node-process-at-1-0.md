# ~node-process@1.0

A singleton node-local process device that uses local names and node configuration to host process-like behavior inside one node.

## When To Use It

- Run node-local processes for operations and services.
- Name process definitions in local node state.
- Expose service behavior without relying on remote scheduling.

## Action Keys

| Key | What it does |
|---|---|
| `definition lookup` | Read process definitions from configured `node_processes`. |
| `local-name integration` | Use `~local-name@1.0` to bind singleton process names. |
| `process delegation` | Delegate behavior to process-compatible devices. |

## Local Examples

Inspect workflow examples show request, configuration, or operator command shapes. Run them only after providing the stated local prerequisites; the browser runner does not execute these blocks.

### Configure a node-local singleton process

```text
cat > /tmp/hb-node-process.flat <<'EOF'
port: 8734
node-processes/counter/device: process@1.0
node-processes/counter/execution-device: lua@5.3a
node-processes/counter/scheduler-device: scheduler@1.0
node-processes/counter/body: function handle(msg) return { count = (count or 0) + 1 } end
priv-wallet: /path/to/operator-wallet.json
EOF
```

Expected: on startup, `~node-process@1.0/counter` can look up or spawn the local process definition named `counter`.

### Look up the singleton process

```text
OPERATOR_NODE="<node-with-counter-process>"
curl -sS "$OPERATOR_NODE/~node-process@1.0/counter/~json@1.0/serialize"
```

Expected: the configured process definition or current local process state. The name is local to this node, not a global ArNS name.

### Register a supporting local name

```text
curl -sS -X POST -H 'content-type: application/json' \
  --data-binary '{"key":"counter","value":{"device":"process@1.0"}}' \
  "<operator-local-node>/~local-name@1.0/register"
```

Expected: operator-signed requests can persist the local name so the singleton survives node restarts.

## Composition

- Use with `~local-name@1.0`, `~process@1.0`, and operator services.

## Trust And Operation

Node-local processes are local operator state. They are convenient but not automatically portable to another node.

## Source

- Root module: `dev_node_process`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
