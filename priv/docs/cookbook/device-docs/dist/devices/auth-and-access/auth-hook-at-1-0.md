# ~auth-hook@1.0

A request hook that signs incoming messages with node-hosted wallets according to operator configuration.

## When To Use It

- Add node-side commitments to incoming messages.
- Use generator devices such as cookie or HTTP auth.
- Build trusted-node authentication and signing workflows.

## Action Keys

| Key | What it does |
|---|---|
| `request hook` | Intercept and sign or reject incoming requests according to configuration. |
| `generator interface` | Call configured auth generators. |
| `wallet selection` | Use node-hosted wallet/secret settings to sign messages. |

## Local Examples

### Install an auth hook that signs Basic-auth requests

```text
cat > /tmp/hb-auth-hook.flat <<'EOF'
port: 8734
on/request/device: auth-hook@1.0
on/request/secret-provider/device: http-auth@1.0
on/request/when/keys/1: authorization
on/request/when/committers: uncommitted
priv-wallet: /path/to/operator-wallet.json
EOF
```

Start a disposable node with that config, then send a request with Basic auth:

```text
AUTH=$(printf 'alice:correct-horse' | base64 | tr -d '\n')
curl -sS -i -H "Authorization: Basic $AUTH" \
  "http://localhost:8734/~message@1.0&body=needs-node-signature/~json@1.0/serialize"
```

Expected: the request hook sees the `authorization` key, derives a secret through `~http-auth@1.0`, creates or finds a node-hosted wallet through `~secret@1.0`, signs the request, then lets normal resolution continue.

### Prove the hook challenges missing credentials

```text
curl -sS -i "http://localhost:8734/~message@1.0&body=needs-node-signature"
```

Expected: with the hook config above, an unsigned request that needs auth returns a Basic challenge or hook error instead of silently signing.

### Use cookie-backed auth instead of Basic auth

```text
cat > /tmp/hb-cookie-hook.flat <<'EOF'
port: 8734
on/request/device: auth-hook@1.0
on/request/secret-provider/device: cookie@1.0
on/request/when/committers: uncommitted
priv-wallet: /path/to/operator-wallet.json
EOF
```

Expected: first request generates/finalizes cookies; subsequent requests present those cookies and the hook signs them with the matching node-hosted wallet.

## Composition

- Use with `~secret@1.0`, `~cookie@1.0`, `~http-auth@1.0`, and `~httpsig@1.0`.

## Trust And Operation

Auth-hook is intentionally trusted-node behavior. Do not rely on an operator to sign for you unless that is the desired trust model.

## Source

- Root module: `dev_auth_hook`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
