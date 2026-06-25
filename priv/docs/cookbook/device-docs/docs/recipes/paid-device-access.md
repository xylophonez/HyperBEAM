# Paid Device Access

HyperBEAM payment devices let an operator wrap ordinary requests with pricing and ledger checks. The core pattern is: estimate before work, charge or settle after work, and expose balances to users.

## Check Payment Configuration

```bash
curl -sS "http://localhost:8734/~meta@1.0/info/format~hyperbuddy@1.0" | grep -i -E 'p4|simple.pay|simple_pay|meter|price|ledger|topup|faff'
```

## Estimate A Simple-Pay Request

```bash
curl -sS \
  -H 'request: path="/~meta@1.0/info/address"' \
  -H 'ao-types: request="map"' \
  "http://localhost:8734/~simple-pay@1.0/estimate"
```

## Read A Balance

```bash
TARGET="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
curl -sS "http://localhost:8734/~simple-pay@1.0/balance?target=$TARGET"
curl -sS "http://localhost:8734/~p4@1.0/balance?target=$TARGET"
```

## Meter A Resource

```bash
curl -sS "http://localhost:8734/~meta@1.0/info/metering-rates/format~hyperbuddy@1.0"
curl -sS "http://localhost:8734/~metering@1.0/estimate"
curl -sS "http://localhost:8734/~metering@1.0/price"
```

These commands become effective when the node has configured ledgers, pricing devices, and signed user/operator requests. On an unconfigured node, the response identifies missing payment state instead of silently allowing paid behavior.

## Composition

```text
request -> p4 request gate -> target device -> p4 response settlement
```

Use `~faff@1.0` for allowlist policy, `~simple-pay@1.0` for flat pricing, and `~metering@1.0` for dynamic resource pricing.
