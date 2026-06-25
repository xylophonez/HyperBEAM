# ~relay@1.0

A relay device for making HTTP calls from a HyperBEAM path. It can fetch local node paths or remote URLs through node-controlled routing.

## When To Use It

- Call another URL as part of a HyperBEAM path.
- Bridge local device output with external HTTP APIs.
- Test route and gateway behavior from the node side.

## Action Keys

| Key | What it does |
|---|---|
| `call` | Perform an HTTP request using `relay-method` and `relay-path`. |
| `relay-method` | The upstream HTTP method, commonly `GET` or `POST`. |
| `relay-path` | The encoded target URL or path to call. |

## Local Examples

### Relay a local node request

```bash
curl -sS "http://localhost:8734/~relay@1.0/call?relay-method=GET&relay-path=http%3A%2F%2Flocalhost%3A8734%2F~meta%401.0%2Finfo%2Faddress"
```

Expected: the same address returned by a direct `~meta@1.0/info/address` call.

### Inspect route policy before relaying external URLs

```bash
curl -sS "http://localhost:8734/~meta@1.0/info/routes/format~hyperbuddy@1.0"
```

Expected: the route configuration visible in the node message. Operator route policy controls which remote URLs may be relayed, so inspect policy before using relay for external APIs.

## Composition

- Use with `~json-iface@1.0` for delegated compute APIs.
- Use with `~arweave@2.9` routes when the node fetches data through a gateway.

## Trust And Operation

Relay output depends on the remote endpoint and the node route policy. Verify signed data separately when remote bytes matter.

## Source

- Root module: `dev_relay`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
