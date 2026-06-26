# Inspect Paid Access Primitives

Payment recipes are operator-sensitive. Balance checks, topups, charges, request gates, and response settlement depend on configured ledgers and signed requests. The public recipe only runs read-only contract and price probes.

## Inspect Metering Contract

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~metering@1.0/docs/schema"
```

Expected: a JSON schema object with metering actions such as `estimate` and `price`.

## Read Zero-Cost Defaults

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~metering@1.0/estimate"
curl -fsS "$HB/~metering@1.0/price"
```

Expected output on docs-test: `0` and `0`.

## Inspect P4 Contract

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~p4@1.0/docs/schema"
```

Expected: a JSON schema object describing P4 actions.

A runnable payment workflow needs a disposable ledger fixture and signed requests inside the workflow before balance, topup, charge, or gate paths can be shown as examples.
