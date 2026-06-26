# ~simple-pay@1.0

A simple flat-pricing ledger device. Operators can configure per-route or per-message pricing, balances, top-ups, and estimates.

## When To Use It

- Prototype paid node access.
- Top up user balances on operator-controlled nodes.
- Estimate and charge simple fixed prices.

## Action Keys

| Key | What it does |
|---|---|
| `balance` | Read a user balance. |
| `estimate` | Estimate the price of a request. |
| `charge` | Deduct price for a request. |
| `topup` | Operator top-up of a user balance. |
| `router-opts/offered` | Route prices exposed to users. |
| `simple_pay_ledger/simple_pay_price` | Node options for ledger and default price. |

## Local Examples

Inspect workflow examples show request, configuration, or operator command shapes. Run them only after providing the stated local prerequisites; the browser runner does not execute these blocks.

### Estimate a normal request

```bash
curl -sS \
  -H 'request: path="/~meta@1.0/info/address"' \
  -H 'ao-types: request="map"' \
  "http://localhost:8734/~simple-pay@1.0/estimate"
```

Expected: `0` for operator requests, a route-specific price if the request matches an offered route, or `simple_pay_price * message_count` for generic requests. Use structured headers for nested request messages; a `request+map=path=/...` query is not safe because `/` is not a structured-field bare item.

### Top up a user balance as the operator

```text
curl -sS -X POST -H 'content-type: application/json' \
  --data-binary '{"target":"USER_ADDRESS","quantity":1000}' \
  "http://localhost:8734/~simple-pay@1.0/topup"
```

Expected: success only for operator/external payment devices allowed to adjust the ledger.

### Check balance and charge

```text
TARGET="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
curl -sS "http://localhost:8734/~simple-pay@1.0/balance?target=$TARGET"
curl -sS \
  -H 'request: path="/~meta@1.0/info/address"' \
  -H 'ao-types: request="map"' \
  "http://localhost:8734/~simple-pay@1.0/charge?quantity+integer=5"
```

Expected: balance returns the ledger amount for a syntactically valid address. Charge subtracts the quantity for a signed request or returns `false`/an authorization response when the request has no chargeable signer.

## Composition

- Use as `p4_ledger-device` or pricing component for P4-style payment gates.

## Trust And Operation

Top-ups and balances are local ledger state. Treat privileged payment paths as mutating policy.

## Source

- Root module: `dev_simple_pay`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
