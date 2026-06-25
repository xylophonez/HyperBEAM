# ~json-iface@1.0

The JSON interface used by WASM and delegated compute engines to exchange process state and messages.

## When To Use It

- Convert HyperBEAM messages for external compute servers.
- Bridge process state into WASM-compatible JSON structures.
- Normalize execution input and output for delegated compute.

## Action Keys

| Key | What it does |
|---|---|
| `to/from` | Convert between HyperBEAM messages and JSON-Iface structures. |
| `message_to_json_struct/json_to_message` | Convert between HyperBEAM messages and JSON-Iface structures. |
| `init/compute` | Initialize or compute using JSON-Iface expectations for VM integrations. |

## Local Examples

Inspect workflow examples show request, configuration, or operator command shapes. Run them only after providing the stated local prerequisites; the browser runner does not execute these blocks.

### Convert a HyperBEAM message to AOS-style JSON

```text
ADDR=$(curl -sS "http://localhost:8734/~meta@1.0/info/address")
curl -sS -X POST -H 'content-type: application/json' \
  --data-binary "{\"data\":\"return 1 + 1\",\"action\":\"Eval\",\"target\":\"$ADDR\",\"from-process\":\"$ADDR\"}" \
  "http://localhost:8734/~json-iface@1.0/to/~json@1.0/serialize"
```

Expected: a JSON-interface object with fields such as `Id`, `Owner`, `Target`, `Tags`, and `Data`. This is the shape expected by AOS/WASM handlers.

### Convert AOS-style output back into a message

```bash
curl -sS -X POST -H 'content-type: application/json' \
  --data-binary '{"Output":{"data":"2"},"Messages":[],"Spawns":[],"Assignments":[]}' \
  "http://localhost:8734/~json-iface@1.0/from/~json@1.0/serialize"
```

Expected: a HyperBEAM message carrying normalized result fields. In a full WASM process, pass 1 writes JSON into the VM environment and pass 2 reads this result back out.

### Use it inside a process definition

```text
cat > /tmp/json-iface-process.json <<'JSON'
{
  "device": "process@1.0",
  "execution-device": "wasm-64@1.0",
  "output-prefix": "results",
  "wasm-device": "json-iface@1.0"
}
JSON
```

Expected: the process/VM stack uses `json-iface@1.0` as the adapter between AO process messages and WASM memory. The standalone conversions above show the exact adapter shape.

## Composition

- Use with `~delegated-compute@1.0`, `~wasm-64@1.0`, and AO process compute flows.

## Trust And Operation

JSON-Iface is an execution format. Verify the process/device commitments around the execution result.

## Source

- Root module: `dev_json_iface`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
