# ~local-name@1.0

A node-local name registry. It stores names in node state and nonvolatile storage so a local operator can bind names to values.

## When To Use It

- Give local names to frequently used IDs.
- Provide operator-controlled aliases during local development.
- Resolve local names before loading cached messages.

## Action Keys

| Key | What it does |
|---|---|
| `lookup` | Read the value for a local name. |
| `register` | Register a key/value pair; this is operator-gated. |
| `info` | Return known name information when exposed by the node. |

## Local Examples

Inspect workflow examples show request, configuration, or operator command shapes. Run them only after providing the stated local prerequisites; the browser runner does not execute these blocks.

### Confirm the local-name device is loaded

```text
curl -sSI "http://localhost:8734/~local-name@1.0/info" | grep -i -E 'status|default|excludes|content-type'
```

Expected: headers showing `status: 200` plus the local-name default function and excluded keys. This is the safe first check because local-name writes are operator-gated.

### Check whether a local name exists

```text
curl -sSI "http://localhost:8734/~local-name@1.0/lookup?key=demo-service" | grep -i -E 'HTTP/|status|content-type'
```

Expected before registration: an HTTP `404` status. That is not a device failure; it means this node has no local value stored under `demo-service` yet.

### Register a local name with an operator signature

```text
OPERATOR_NODE="<operator-node-you-control>"
curl -sS -i -X POST -H 'content-type: application/json' \
  --data-binary '{"key":"demo-service","value":{"device":"message@1.0","body":"hello local name"}}' \
  "$OPERATOR_NODE/~local-name@1.0/register"
```

Expected: `Registered.` only when the request is signed by the node operator. A normal unsigned `curl` against a claimed node should return `403 Unauthorized`; a missing route or unavailable hashpath can return `404`. The edge test for this path posts a committed message, equivalent to:

```erlang
hb_http:post(
    Node,
    <<"/~local-name@1.0/register">>,
    hb_message:commit(
        #{ <<"key">> => <<"demo-service">>,
           <<"value">> => #{ <<"body">> => <<"hello local name">> } },
        Opts
    ),
    Opts
).
```

Use this from a node/operator context where `Opts` carries the operator wallet. Do not expect a public preview node to register names for you.

### Look up an operator-registered name

```text
OPERATOR_NODE="<operator-node-you-control>"
curl -sS "$OPERATOR_NODE/~local-name@1.0/lookup?key=demo-service"
```

Expected after a successful operator registration: the message registered under `demo-service`.

### Use default lookup syntax after registration

```text
OPERATOR_NODE="<operator-node-you-control>"
curl -sS "$OPERATOR_NODE/~local-name@1.0/demo-service/body"
```

Expected after a successful operator registration: `hello local name`. The device's default key delegates to lookup.

## Composition

- Use with `~name@1.0` as one resolver source.
- Use with `~cache@1.0` to give short names to cached messages.

## Trust And Operation

Local names are local operator state. A name on one node does not imply the same value on another node.

## Source

- Root module: `dev_local_name`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
