# Read Meta Node Information

`~meta@1.0` is the node boundary device. This recipe reads public node identity and build fields without changing operator configuration.

## Read The Node Address

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~meta@1.0/info/address"
```

Expected: JSON with `body` set to the node address.

## Read Build Identity

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~meta@1.0/build/node"
curl -fsS "$HB/~meta@1.0/build/version"
```

Expected: JSON responses with `body` equal to `HyperBEAM` and the node version.

## Inspect The Public Node Message

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~meta@1.0/info"
```

Expected: a public node message with private keys filtered out.
