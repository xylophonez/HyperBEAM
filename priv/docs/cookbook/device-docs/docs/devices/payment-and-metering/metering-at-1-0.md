# ~metering@1.0

A dynamic pricing device for P4. It opens metering sessions, records consumption, and calculates final prices from configured rates.

## When To Use It

- Charge for bytes, compute time, or other measured resources.
- Price long-running operations after usage is known.
- Meter bundler byte usage.

## Action Keys

| Key | What it does |
|---|---|
| `estimate` | Open or estimate a metering session. |
| `consume` | Increment usage for a named resource. |
| `price` | Close/finalize price for a session. |
| `is_active` | Check whether a metering session is active. |
| `metering-rates` | Node configuration for resource prices. |

## Local Examples

### Configure metering as P4 pricing

```text
cat > /tmp/hb-p4-metering.flat <<'EOF'
on/request/device: p4@1.0
on/request/pricing-device: metering@1.0
on/request/ledger-device: simple-pay@1.0
on/response/device: p4@1.0
on/response/pricing-device: metering@1.0
on/response/ledger-device: simple-pay@1.0
metering-rates/arweave-bytes: 2
metering-rates/beam-reductions: 0
EOF
```

Expected: request processing opens a metering session; response processing closes it and charges based on resources consumed.

### Open and close a metering session directly

```bash
curl -sS "http://localhost:8734/~metering@1.0/estimate"
curl -sS "http://localhost:8734/~metering@1.0/price"
```

Expected: `estimate` returns `0` and starts process-local accounting; `price` returns the calculated price and clears the session. Direct calls only meter work done in the same resolution process.

### Meter Arweave bytes from a bundler flow

```text
curl -sS -X POST -H 'content-type: application/octet-stream' \
  --data-binary @signed-item.bin \
  "http://localhost:8734/~bundler@1.0/item?codec-device=ans104@1.0"
```

Expected: on a node with the P4 metering config, bundler/arweave code can call the metering helper API so final price reflects bytes/chunks/reductions used.

## Composition

- Use with `~bundler@1.0` for byte metering.
- Use as P4 pricing component for dynamic costs.

## Trust And Operation

Metering affects money-like state. Use signed sessions and operator-controlled configuration.

## Source

- Root module: `dev_metering`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
