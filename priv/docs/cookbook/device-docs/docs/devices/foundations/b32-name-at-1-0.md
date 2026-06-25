# ~b32-name@1.0

A name resolver for base32 subdomains that point at Arweave message IDs.

## When To Use It

- Resolve Arweave IDs encoded into hostnames.
- Serve gateway-style requests where the host carries the content identity.
- Bridge DNS-like addressing into HyperBEAM resolution.

## Action Keys

| Key | What it does |
|---|---|
| `request/default` | Interpret a request host or name value as a base32-encoded target. |
| `resolver behavior` | Participates as a resolver behind `~name@1.0` when configured. |

## Local Examples

### Resolve a base32 subdomain back to an Arweave ID

```bash
B32_HOST="<52-character-base32-id>.localhost"
curl -sS -H "Host: $B32_HOST" "http://localhost:8734/index.html"
```

Expected: `b32-name@1.0` decodes the subdomain into the original 43-character Arweave/HyperBEAM ID and resolves the remaining path against that message.

### Compare with a normal ID path

```bash
HB="<node-with-b32-name-resolver>"
ID="<decoded-43-character-id>"
curl -sS "$HB/$ID/index.html"
```

Expected: the subdomain and explicit-ID forms resolve to the same content when resolver configuration and manifest data are available.

### Use b32-name in the resolver chain

```bash
cat > /tmp/hb-b32-name.flat <<'EOF'
name-resolvers/1/device: b32-name@1.0
name-resolvers/2/device: local-name@1.0
EOF
```

Expected: hostnames that look like base32 IDs resolve before local names or other resolver devices.

## Composition

- Use behind `~name@1.0` and before `~cache@1.0` or `~arweave@2.9` reads.

## Trust And Operation

The decoded target may be content-addressed, but host routing and resolver configuration are local policy.

## Source

- Root module: `dev_b32_name`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
