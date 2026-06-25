# ~delegated-compute@1.0

A wrapper for compute on remote machines that implement the JSON-Iface.

## When To Use It

- Bring trusted remote compute results into a local node.
- Use a remote server as a process execution device.
- Snapshot or compute through a JSON-Iface endpoint.

## Action Keys

| Key | What it does |
|---|---|
| `init/normalize` | Prepare delegated compute state. |
| `compute` | Call the remote compute endpoint and convert JSON-Iface output back to a message. |
| `snapshot` | Ask the remote server for state snapshot. |

## Local Examples

### Delegate compute to a local worker endpoint

```bash
HB="<local-node-with-json-iface-worker>"
cat > /tmp/delegated-request.json <<JSON
{
  "compute-server": "$HB",
  "request": {"device":"message@1.0", "path":"body", "body":"hello"}
}
JSON
curl -sS -X POST --data-binary @/tmp/delegated-request.json \
  "$HB/~delegated-compute@1.0/compute/~json@1.0/serialize"
```

Expected: the device forwards the compute-shaped request to the configured endpoint and returns the worker response. Use a real remote URL when separating schedulers from compute workers.

### Pair with JSON-Iface for process compute

```bash
ADDR=$(curl -sS "http://localhost:8734/~meta@1.0/info/address")
curl -sS "http://localhost:8734/~json-iface@1.0/to&data=ping&action=Eval&target=$ADDR&from-process=$ADDR/~json@1.0/serialize"
```

Expected: `json-iface@1.0` prepares the message shape that delegated WASM/AOS workers commonly expect.

### Require separate verification for delegated results

```bash
curl -sS -D /tmp/delegated.headers "http://localhost:8734/~meta@1.0/info/address" -o /tmp/delegated.body
sed -n '/^signature:/Ip;/^signature-input:/Ip' /tmp/delegated.headers
```

Expected: verify signatures or commitments on delegated responses before using them as authoritative state.

## Composition

- Uses `~relay@1.0` and `~json-iface@1.0` to call remote compute workers.
- Can be an execution device under `~process@1.0`.

## Trust And Operation

Delegated compute is a trust boundary. Treat the remote server as part of your trusted computing base unless its result is separately verified.

## Source

- Root module: `dev_delegated_compute`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
