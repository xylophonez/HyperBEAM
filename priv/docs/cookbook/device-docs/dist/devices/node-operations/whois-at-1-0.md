# ~whois@1.0

A small device for request and node network identity information.

## When To Use It

- Show what IP/host data the node sees for a request.
- Debug reverse proxies and local networking.
- Expose node identity information in operator tools.

## Action Keys

| Key | What it does |
|---|---|
| `echo` | Return request-side network information. |
| `node` | Return the public node URL known to the server. |

## Local Examples

Inspect workflow examples show request, configuration, or operator command shapes. Run them only after providing the stated local prerequisites; the browser runner does not execute these blocks.

### Return request-side network information

```bash
curl -sS "http://localhost:8734/~whois@1.0/echo"
```

Expected: request-side information such as host/peer details visible to the node. A local direct request commonly returns `unknown` when no peer metadata has been set.

### Return the node URL

```bash
curl -sS "http://localhost:8734/~whois@1.0/node"
```

Expected: the URL this node reports for itself, such as `http://localhost:8734` locally or the public HTTPS origin on a hosted node.

### Compare network identity with signing identity

```text
curl -sS "http://localhost:8734/~meta@1.0/info/address"
curl -sS "http://localhost:8734/~whois@1.0/node"
```

Expected: `meta/address` identifies the signing wallet; `whois` reports the URL the node uses for network reachability.

## Composition

- Use in operator dashboards and debugging recipes.

## Trust And Operation

Network data may reflect proxies, local binds, or forwarded headers.

## Source

- Root module: `dev_whois`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
