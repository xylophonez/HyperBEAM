# Inspect The Transaction Codec

`~tx@1.0` maps AO-Core messages to Arweave L1 transaction commitments. Signing and full transaction round trips require real transaction material, so this public recipe verifies the stable codec contract.

## Inspect The Codec Schema

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~tx@1.0/info/schema"
```

Expected: a JSON schema object with `to`, `commit`, and `verify` actions.

## Inspect Commitment Actions

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~tx@1.0/info/schema/commit"
curl -fsS "$HB/~tx@1.0/info/schema/verify"
```

Expected: JSON describing the unsigned or signed commitment request and the verification action.

Do not publish a transaction round-trip recipe unless it provides the exact transaction fixture, signing material, or generated commitment bytes needed by every step.
