# ~location@1.0

A peer-location device. It creates, caches, and reads signed location records that tell other nodes how to reach a HyperBEAM peer.

## When To Use It

- Advertise this node as reachable.
- Cache known peer location records.
- Resolve an address to known peer endpoint data.

## Action Keys

| Key | What it does |
|---|---|
| `node` | Generate or register this node location record. |
| `known` | Accept and cache a valid peer location record. |
| `<address>` | Read a known location record for a node address. |

## Local Examples

Inspect workflow examples show request, configuration, or operator command shapes. Run them only after providing the stated local prerequisites; the browser runner does not execute these blocks.

### Publish this node's current location record

```bash
curl -sS "http://localhost:8734/~location@1.0/node/~json@1.0/serialize"
```

Expected: a signed location message for this node address and URL/nonce. Nodes use this so peers know where an address can be reached.

### Read a known node location

```text
ADDR=$(curl -sS "http://localhost:8734/~meta@1.0/info/address")
curl -sS "http://localhost:8734/~location@1.0/$ADDR/~json@1.0/serialize"
```

Expected: the latest cached location record for that address, if one has been registered.

### List all known local locations

```bash
curl -sS "http://localhost:8734/~location@1.0/all/~json@1.0/serialize"
```

Expected: all location records currently known to this node.

## Composition

- Use with `~router@1.0` and peer discovery workflows.
- Use with `~httpsig@1.0` because location records should be verifiable.

## Trust And Operation

A location record is useful only if its signature and freshness match your routing policy.

## Source

- Root module: `dev_location`
- Helper modules: `dev_location_cache`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
