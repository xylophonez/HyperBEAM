# ~patch@1.0

A data-shaping device that moves values between message paths. It can operate as ordinary patch application or as part of stack/process compute lifecycle.

## When To Use It

- Normalize message shape before compute.
- Move process outputs into the paths expected by another device.
- Apply patch lists in stack recipes.

## Action Keys

| Key | What it does |
|---|---|
| `all` | Apply all configured patches. |
| `patches` | Read patch instructions from the request/base. |
| `compute/init/snapshot/normalize` | Lifecycle actions used when patch participates in process stacks. |

## Local Examples

Inspect workflow examples show request, configuration, or operator command shapes. Run them only after providing the stated local prerequisites; the browser runner does not execute these blocks.

### Export a process table as direct HTTP state

Inside a Lua process, send patch messages whenever state changes:

```lua
Balances = Balances or {}
Handlers.add('Credit', function(msg)
  Balances[msg.Account] = (Balances[msg.Account] or 0) + tonumber(msg.Quantity)
  ao.send({
    device = 'patch@1.0',
    cache = { balances = { [msg.Account] = Balances[msg.Account] } }
  })
end)
```

Then read the patched state through process paths:

```bash
HB="${HB:-http://localhost:8734}"
PROCESS_ID="co-MIhejkMR8v3-oIvW8m_u3YfV7zXoII0ja1wk-IOo"
curl -fsS "$HB/$PROCESS_ID~process@1.0/compute/counter"
```

Expected: the latest exported counter without performing a fresh dry run.

### Apply a patch message directly

```text
curl -sS -X POST -H 'content-type: application/json' \
  --data-binary '{"cache":{"profile":{"name":"alice","role":"operator"}}}' \
  "http://localhost:8734/~patch@1.0/all/~json@1.0/serialize"
```

Expected: patch merges the supplied cache fragment into the target message/state according to the patch definition.

### Patch only the changed key

```text
curl -sS -X POST -H 'content-type: application/json' \
  --data-binary '{"cache":{"orders":{"order-123":{"status":"paid"}}}}' \
  "http://localhost:8734/~patch@1.0/all/~json@1.0/serialize"
```

Expected: only `orders/order-123/status` needs to be exported; clients can read that key directly through the process cache path.

## Composition

- Use before Lua/WASM when input keys do not match function expectations.
- Use after compute to shape outputs for `~push@1.0`.

## Trust And Operation

Patch changes message shape. Audit patch definitions in signed process messages before trusting downstream output.

## Source

- Root module: `dev_patch`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
