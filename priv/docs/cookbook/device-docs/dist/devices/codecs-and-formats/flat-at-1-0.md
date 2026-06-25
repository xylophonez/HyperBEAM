# ~flat@1.0

A codec that flattens nested TABM messages into path-keyed maps and can expand them again.

## When To Use It

- Represent nested messages as simple path maps.
- Diff message structure with stable path keys.
- Prepare data for storage formats that prefer flat keys.

## Action Keys

| Key | What it does |
|---|---|
| `to` | Convert a nested message into flat path-keyed form. |
| `from` | Rebuild a nested message from flat path-keyed form. |
| `serialize/deserialize` | Encode or decode the flat representation. |

## Local Examples

### Flatten a nested message into slash-key form

```text
HB="<local-node-with-flat-codec>"
curl -sS -X POST -H 'content-type: application/json' \
  --data-binary '{"user":{"name":"alice","role":"operator"},"count":3}' \
  "$HB/~flat@1.0/to/~json@1.0/serialize"
```

Expected: keys such as `user/name` and `user/role` appear in the result. This is useful for config files and simple line-oriented review.

### Parse a flat config into a nested message

```text
HB="<local-node-with-flat-codec>"
printf 'user/name: alice\nuser/role: operator\ncount: 3\n' >/tmp/demo.flat
curl -sS -X POST --data-binary @/tmp/demo.flat \
  "$HB/~flat@1.0/deserialize/~json@1.0/serialize"
```

Expected: a nested message equivalent to `{"user":{"name":"alice","role":"operator"},"count":"3"}`. Use `structured@1.0` when numeric type recovery matters.

### Use flat config to start a node

```text
cat > /tmp/hb-minimal.flat <<'EOF'
port: 8734
store: rocksdb@1.0
priv-wallet: /path/to/operator-wallet.json
load-remote-devices: false
trusted-device-signers/1: <trusted-signer-address>
routes/1/template: /~arweave@2.9/*
routes/1/node: https://arweave.net
EOF
```

Expected: HyperBEAM's config loader uses `flat@1.0` for `.flat` files, turning slash-key lines such as `routes/1/template` into nested node configuration. Replace the wallet path and signer address before using this on an operator node.

## Composition

- Use with `~cache@1.0`, `~query@1.0`, and operator tooling that indexes paths.

## Trust And Operation

Flattening changes representation, not authority. Verify the original committed message when required.

## Source

- Root module: `dev_flat`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
