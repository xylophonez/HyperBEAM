# ~name@1.0

A resolver device for turning names into values through configured resolver messages.

## When To Use It

- Resolve human or configured names to message IDs or values.
- Build friendly entrypoints on top of pinned IDs.
- Chain multiple resolver sources until one matches.

## Action Keys

| Key | What it does |
|---|---|
| `request` | Resolve the requested key through the configured resolver list. |
| `default` | Unknown path keys are treated as names to resolve. |
| `name-resolvers` | Resolver configuration is read from the node message. |

## Local Examples

### Inspect configured name resolvers

```text
curl -sS "http://localhost:8734/~meta@1.0/info/name-resolvers/~json@1.0/serialize"
```

Expected: the resolver configuration for this node when present, or a clear missing-key response if the operator has not configured name resolvers. Configure resolvers before expecting arbitrary names to resolve.

### Use local-name as one resolver

```text
cat > /tmp/hb-name-resolvers.flat <<'EOF'
name-resolvers/1/device: local-name@1.0
name-resolvers/2/device: b32-name@1.0
EOF
```

Expected: `~name@1.0/foo` checks local names first, then base32 host/ID resolution.

### Resolve a configured name then continue the path

```text
http://localhost:8734/~name@1.0/NAME_FROM_YOUR_RESOLVER/body
```

Expected after `NAME_FROM_YOUR_RESOLVER` resolves to a message: `/body` is applied to that resolved message.

## Composition

- Use before `~cache@1.0` to turn names into cache locations.
- Use with trusted device specs so operators can load friendly names.

## Trust And Operation

Name resolution is only as trustworthy as the resolver messages your node uses.

## Source

- Root module: `dev_name`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
