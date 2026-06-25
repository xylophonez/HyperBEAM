# ~faff@1.0

A friends-and-family allowlist pricing device. It allows configured addresses to access service cheaply or freely while estimating/charging others.

## When To Use It

- Operate invite-only or allowlisted nodes.
- Prototype non-public payment policy.
- Blend allowlist checks with P4 pricing.

## Action Keys

| Key | What it does |
|---|---|
| `estimate` | Estimate price based on allowlist membership. |
| `charge` | Charge or waive according to policy. |
| `faff allowlist config` | Operator-provided friends/family addresses and pricing behavior. |

## Local Examples

### Configure friends-and-family payment policy

```text
cat > /tmp/hb-faff.flat <<'EOF'
on/request/device: p4@1.0
on/request/pricing-device: faff@1.0
on/request/ledger-device: faff@1.0
faff-allow-list/1: ALLOWED_ADDRESS
EOF
```

Expected: P4 asks `faff@1.0` whether all request signers are in `faff-allow-list`.

### Estimate for an allowed signed request

```text
curl -sS -X POST -H 'content-type: application/json' \
  --data-binary '{"request":{"path":"/~meta@1.0/info/address"}}' \
  "http://localhost:8734/~faff@1.0/estimate"
```

Expected: `0` when every signer is allowlisted; `infinity` when any signer is missing.

### Use FAFF as a no-charge ledger

```text
curl -sS "http://localhost:8734/~faff@1.0/charge?quantity+integer=100&request+map=path=/~meta@1.0/info/address"
```

Expected: `true`. FAFF does not debit balances; it is an allow/deny pricing policy for private nodes.

## Composition

- Use as a P4 pricing device or policy layer before expensive services.

## Trust And Operation

Allowlist behavior is local operator policy.

## Source

- Root module: `dev_faff`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
