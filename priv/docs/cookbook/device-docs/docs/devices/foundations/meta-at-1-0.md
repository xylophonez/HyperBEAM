# ~meta@1.0

The node entrypoint and configuration surface. It returns the public node message, exposes build information, and answers operator checks.

## When To Use It

- Check that a node is alive.
- Read public node configuration and preloaded device settings.
- Check hooks, routes, payment policy, and trusted-device configuration before using operator devices.

## Action Keys

| Key | What it does |
|---|---|
| `info` | Return the filtered public node message. A nested path such as `info/address` reads one key from that message. |
| `build` | Return HyperBEAM build metadata when available. |
| `is-operator` | Return whether the signed body request is from the node operator. |

## Local Examples

Inspect workflow examples show request, configuration, or operator command shapes. Run them only after providing the stated local prerequisites; the browser runner does not execute these blocks.

### Read the node address for signatures and operator checks

```text
curl -sS "http://localhost:8734/~meta@1.0/info/address"
```

Expected: the node's public address. Use this to know which key signs local responses.

### Read the preloaded device index

```text
curl -sS "http://localhost:8734/~meta@1.0/info/preloaded-devices-index"
```

Expected: the content ID of the build-time preloaded device index.

### Check remote-device loading policy

```text
curl -sS "http://localhost:8734/~meta@1.0/info/load-remote-devices"
curl -sS "http://localhost:8734/~meta@1.0/info/trusted-device-signers/~json@1.0/serialize"
curl -sS "http://localhost:8734/~meta@1.0/info/trusted-devices/~json@1.0/serialize"
```

Expected: whether this node may fetch remote devices, which signers it trusts, and which implementation IDs are pinned.

### Use meta as the default request pipeline

```text
curl -sS -D - "http://localhost:8734/~message@1.0&body=through-meta/body" -o /dev/null \
  | grep -i -E 'HTTP/|ao-result:|status:|content-type'
curl -sS "http://localhost:8734/~message@1.0&body=through-meta/body"
```

Expected: the first command shows HTTP response metadata produced by the meta pipeline, and the second command returns `through-meta`. Even simple device calls pass through meta preprocessing/postprocessing; inspect the full response headers when you need the signature material.

## Composition

- Use before any operator recipe to understand the node you are about to call.
- Pipe `info` into `~json@1.0` when clients need structured configuration.

## Trust And Operation

`info` is local node state. It tells you how this node is configured, not a global truth about other nodes.

## Source

- Root module: `dev_meta`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
