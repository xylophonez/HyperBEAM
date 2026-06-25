# ~router@1.0

The outbound routing device. It selects routes from node configuration and supports strategies such as random, by-base, and nearest.

## When To Use It

- Choose where a request should be sent.
- Expose or modify route tables on operator-controlled nodes.
- Support peer-aware routing and gateway composition.

## Action Keys

| Key | What it does |
|---|---|
| `route` | Select a route for a request. |
| `routes` | Return or update known route configuration. |
| `register` | Register a route in node state when authorized. |
| `match` | Match a request against configured route rules. |
| `preprocess` | Prepare route data before dispatch. |

## Local Examples

### Register a route as the operator

```bash
curl -sS -X POST -H 'content-type: application/json' \
  --data-binary '{"template":"/~meta@1.0/*","node":"http://localhost:8734","priority":10,"strategy":"Random"}' \
  "http://localhost:8734/~router@1.0/routes"
```

Expected: `Route added.` when signed by an authorized route owner; otherwise `not_authorized`. Routes are mutable operator policy.

### Match a request against the route table

```bash
curl -sS "http://localhost:8734/~router@1.0/match?route-path=/~meta@1.0/info/address"
```

Expected: the route that would handle the local meta path, including node/strategy fields when a matching route is configured.

### Route by base for deterministic workers

```bash
curl -sS -G "http://localhost:8734/~router@1.0/route" \
  --data-urlencode 'route-path=/PROCESS_ID~process@1.0/compute' \
  --data-urlencode 'route-by=PROCESS_ID'
```

Expected: the same process/hashpath consistently maps to the same worker when a `By-Base` route is configured.

### Offer this node to a remote router

```bash
cat > /tmp/hb-router-offer.flat <<'EOF'
router-opts/offered/1/registration-peer: http://router.example:8734
router-opts/offered/1/prefix: /~meta@1.0
router-opts/offered/1/template: /~meta@1.0/*
router-opts/offered/1/price: 1
EOF
curl -sS "http://localhost:8734/~router@1.0/register"
```

Expected: the node posts a signed route registration to the peer router.

## Composition

- Use with `~relay@1.0`, `~location@1.0`, and Arweave gateway access.

## Trust And Operation

Routes are operator policy. A route result tells you what this node will do, not what every node will do.

## Source

- Root module: `dev_router`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
