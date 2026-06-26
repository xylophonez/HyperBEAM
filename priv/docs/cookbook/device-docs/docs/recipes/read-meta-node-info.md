# Read Meta Node Information

`~meta@1.0` is the node boundary device. This recipe reads public node identity and build fields without changing operator configuration.

## Read The Node Address

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~meta@1.0/info/address"
```

Expected: the node address.

## Read Build Identity

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~meta@1.0/build/node"
printf '\n'
curl -fsS "$HB/~meta@1.0/build/version"
```

Expected: `HyperBEAM` and the node version.

## Inspect The Public Node Message

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~meta@1.0/info/~json@1.0/serialize"
```

Expected: a JSON object for the public node message with private keys filtered out.
